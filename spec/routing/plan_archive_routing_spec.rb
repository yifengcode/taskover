require 'rails_helper'

RSpec.describe 'plan archive routes', type: :routing do
  %w[archive unarchive].each do |action|
    it "routes PUT /p/:ident/#{action}.json to plans##{action}" do
      expect(:put => "/p/release1/#{action}.json").to route_to(
        :controller => 'plans', :action => action, :id => 'release1', :format => 'json'
      )
    end

    [:get, :post, :delete].each do |verb|
      it "does not route #{verb.to_s.upcase} /p/:ident/#{action}.json" do
        expect(verb => "/p/release1/#{action}.json").not_to be_routable
      end
    end
  end
end
