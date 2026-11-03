require 'rails_helper'
require 'execjs'

RSpec.describe 'plans archiving controls', type: :view do
  # Exercise the rendered Vue methods without a browser or a live HTTP service.
  # Vue only binds data and methods here; lifecycle hooks are outside these units.
  let(:javascript_harness) do
    <<~JS
      var requests = [];
      var notifications = [];
      var gon = { plan_ident: 'release1' };
      function Vue(options) {
        var instance = options.data;
        Object.keys(options.methods).forEach(function(name) {
          instance[name] = options.methods[name].bind(instance);
        });
        return instance;
      }
      function XMLHttpRequest() {
        requests.push(this);
        this.headers = {};
      }
      XMLHttpRequest.prototype.open = function(method, url) {
        this.method = method;
        this.url = url;
      };
      XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        this.headers[name] = value;
      };
      XMLHttpRequest.prototype.send = function() { this.sent = true; };
      XMLHttpRequest.prototype.respond = function(body) {
        this.responseText = JSON.stringify(body);
        this.onload();
      };
      function notifyTop(message, severity) {
        notifications.push([message, severity || null]);
      }
    JS
  end
  let(:document) { Nokogiri::HTML.fragment(rendered) }
  let(:javascript_context) do
    scripts = document.css('script').map(&:text).join("\n")
    expect(scripts).not_to be_empty
    # Node parses the ES6 methods present elsewhere in the detail page's script.
    ExecJS::Runtimes::Node.compile(javascript_harness + scripts)
  end

  def evaluate_javascript(source)
    javascript_context.eval("(function() { #{source} })()")
  end

  describe 'the plan index' do
    before { render template: 'plans/index', formats: [:html] }

    it 'offers archive and unarchive controls for the corresponding list state' do
      archive = document.css('i').find { |node| node['v-on:click'] == 'archivePlan(plan)' }
      unarchive = document.css('i').find { |node| node['v-on:click'] == 'unarchivePlan(plan)' }

      expect(archive).not_to be_nil
      expect(unarchive).not_to be_nil
      expect(archive['v-show']).to eq('!showArchived')
      expect(unarchive['v-show']).to eq('showArchived')
    end

    it 'hides editing and new-plan controls in the archived list' do
      expect(document.at_css('.icon-pencil')['v-show']).to eq('!showArchived')
      expect(document.at_css('#add-plan-field').parent['v-show'])
        .to eq('!showArchived && newPlanField')
      expect(document.at_css('#add-plan-entry').parent['v-show'])
        .to eq('!showArchived && !!!newPlanField')
    end

    it 'fetches active plans by default and loads the response into the list' do
      result = evaluate_javascript(<<~JS)
        plans_list.fetchData();
        requests[0].respond([{ident: 'active01', archived: false}]);
        return {method: requests[0].method, url: requests[0].url,
                sent: requests[0].sent, plans: plans_list.plans};
      JS

      expect(result).to eq('method' => 'GET', 'url' => '/p.json', 'sent' => true,
                           'plans' => [{ 'ident' => 'active01', 'archived' => false }])
    end

    it 'fetches archived plans when switching to the archive list' do
      result = evaluate_javascript(<<~JS)
        plans_list.showArchivedPlans();
        requests[0].respond([{ident: 'archive1', archived: true}]);
        return {archived: plans_list.showArchived, url: requests[0].url,
                plans: plans_list.plans};
      JS

      expect(result).to eq('archived' => true, 'url' => '/p.json?archived=true',
                           'plans' => [{ 'ident' => 'archive1', 'archived' => true }])
    end

    it 'clears the archive filter when returning to active plans' do
      result = evaluate_javascript(<<~JS)
        plans_list.showArchived = true;
        plans_list.showActivePlans();
        return {archived: plans_list.showArchived, url: requests[0].url};
      JS

      expect(result).to eq('archived' => false, 'url' => '/p.json')
    end

    %w[archive unarchive].each do |action|
      it "sends a PUT to #{action} the selected plan and removes only that plan on success" do
        result = evaluate_javascript(<<~JS)
          var first = {ident: 'first001'}, target = {ident: 'release1'}, last = {ident: 'last0001'};
          plans_list.plans = [first, target, last];
          plans_list.#{action}Plan(target);
          requests[0].respond({status: 'success', message: 'Done'});
          return {method: requests[0].method, url: requests[0].url,
                  headers: requests[0].headers, sent: requests[0].sent,
                  plans: plans_list.plans, notifications: notifications};
        JS

        expect(result).to eq('method' => 'PUT', 'url' => "/p/release1/#{action}.json",
                             'headers' => { 'Content-type' => 'application/x-www-form-urlencoded' },
                             'sent' => true, 'plans' => [{ 'ident' => 'first001' }, { 'ident' => 'last0001' }],
                             'notifications' => [['Done', nil]])
      end

      it "keeps the list unchanged and shows an error when #{action} fails" do
        result = evaluate_javascript(<<~JS)
          var target = {ident: 'release1'}, other = {ident: 'other001'};
          plans_list.plans = [target, other];
          plans_list.#{action}Plan(target);
          requests[0].respond({status: 'failed', message: 'Try again'});
          return {plans: plans_list.plans, notifications: notifications};
        JS

        expect(result).to eq('plans' => [{ 'ident' => 'release1' }, { 'ident' => 'other001' }],
                             'notifications' => [['Try again', 'danger']])
      end
    end
  end

  describe 'the plan details' do
    before { render template: 'plans/show', formats: [:html] }

    it 'offers the appropriate controls and an archive notice based on the plan status' do
      archive = document.css('i').find { |node| node['v-on:click'] == 'archivePlan' }
      unarchive = document.css('i').find { |node| node['v-on:click'] == 'unarchivePlan' }

      expect(archive).not_to be_nil
      expect(unarchive).not_to be_nil
      expect(archive['v-show']).to eq('!plan.archived')
      expect(unarchive['v-show']).to eq('plan.archived')
      expect(document.at_css('.archived-tip')['v-show']).to eq('plan.archived')
    end

    { 'archive' => [false, true], 'unarchive' => [true, false] }.each do |action, states|
      initial_state, final_state = states

      it "uses the supplied #{action} URL and updates the local status after success" do
        result = evaluate_javascript(<<~JS)
          lists_tasks.plan.archived = #{initial_state};
          lists_tasks.plan.#{action}_path = '/custom/#{action}.json';
          lists_tasks.#{action}Plan();
          requests[0].respond({status: 'success', message: 'Done'});
          return {method: requests[0].method, url: requests[0].url,
                  headers: requests[0].headers, sent: requests[0].sent,
                  archived: lists_tasks.plan.archived, notifications: notifications};
        JS

        expect(result).to eq('method' => 'PUT', 'url' => "/custom/#{action}.json",
                             'headers' => { 'Content-type' => 'application/x-www-form-urlencoded' },
                             'sent' => true, 'archived' => final_state,
                             'notifications' => [['Done', nil]])
      end

      it "leaves the local status unchanged and shows an error when #{action} fails" do
        result = evaluate_javascript(<<~JS)
          lists_tasks.plan.archived = #{initial_state};
          lists_tasks.#{action}Plan();
          requests[0].respond({status: 'failed', message: 'Try again'});
          return {archived: lists_tasks.plan.archived, notifications: notifications};
        JS

        expect(result).to eq('archived' => initial_state,
                             'notifications' => [['Try again', 'danger']])
      end
    end
  end
end
