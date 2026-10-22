require 'rails_helper'

RSpec.describe PlansController, type: :controller do
  # Use the existing truncation cleaner without a conflicting fixture transaction.
  self.use_transactional_tests = false

  include Devise::Test::ControllerHelpers
  render_views

  let(:user) do
    User.create!(ident: 'archive-owner', email: 'archive-owner@example.com',
                 password: 'password123', confirmed_at: Time.current)
  end
  let(:other_user) do
    User.create!(ident: 'other-owner', email: 'other-owner@example.com',
                 password: 'password123', confirmed_at: Time.current)
  end

  before { sign_in user }

  def response_json
    JSON.parse(response.body)
  end

  describe 'GET #index as JSON' do
    let!(:first_active) { user.plans.create!(title: 'First active', ident: 'active01') }
    let!(:second_active) { user.plans.create!(title: 'Second active', ident: 'active02') }
    let!(:first_archived) do
      user.plans.create!(title: 'First archived', ident: 'archive1', archived: true)
    end
    let!(:second_archived) do
      user.plans.create!(title: 'Second archived', ident: 'archive2', archived: true)
    end

    before do
      other_user.plans.create!(title: 'Foreign active', ident: 'foreign1')
      other_user.plans.create!(title: 'Foreign archived', ident: 'foreign2', archived: true)
      user.plan_sort.update!(sort: [second_archived.id, second_active.id,
                                    first_archived.id, first_active.id])
    end

    it 'defaults to the current user\'s active plans in saved order' do
      get :index, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json.map { |entry| entry.fetch('id') })
        .to eq([second_active.id, first_active.id])
      expect(response_json.map { |entry| entry.fetch('archived') }).to eq([false, false])
    end

    it 'returns only the current user\'s archived plans in saved order for archived=true' do
      get :index, params: { archived: 'true' }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json.map { |entry| entry.fetch('id') })
        .to eq([second_archived.id, first_archived.id])
      expect(response_json.map { |entry| entry.fetch('archived') }).to eq([true, true])
    end

    ['false', '', '1', 'TRUE', 'True', 'true '].each do |value|
      it "keeps the active filter for archived=#{value.inspect}" do
        get :index, params: { archived: value }, format: :json

        expect(response).to have_http_status(:ok)
        expect(response_json.map { |entry| entry.fetch('id') })
          .to eq([second_active.id, first_active.id])
      end
    end

    [false, true].each do |archived|
      it "returns an empty array when the user has no #{archived ? 'archived' : 'active'} plans" do
        user.plans.where(archived: archived).destroy_all

        get :index, params: { archived: archived.to_s }, format: :json

        expect(response).to have_http_status(:ok)
        expect(response_json).to eq([])
      end

      it "handles #{archived ? 'archived' : 'active'} plans when the user has no saved order" do
        user.plan_sort.destroy!
        user.reload

        get :index, params: { archived: archived.to_s }, format: :json

        expected_plans = archived ? [first_archived, second_archived] : [first_active, second_active]
        expect(response).to have_http_status(:ok)
        expect(response_json.map { |entry| entry.fetch('id') })
          .to match_array(expected_plans.map(&:id))
      end
    end
  end

  shared_examples 'a plan archive endpoint' do |action, initial_state, final_state, success_message, failure_message|
    let!(:plan) do
      user.plans.create!(title: 'Release', ident: 'release1', archived: initial_state)
    end

    it 'persists the transition and returns the archive status as a JSON boolean' do
      put action, params: { id: plan.ident }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json).to eq('status' => 'success', 'message' => success_message,
                                  'archived' => final_state)
      expect(plan.reload.archived?).to eq(final_state)
    end

    it 'succeeds when the plan is already in the requested state' do
      plan.update!(archived: final_state)

      expect do
        put action, params: { id: plan.ident }, format: :json
      end.not_to change(Plan, :count)

      expect(response).to have_http_status(:ok)
      expect(response_json).to eq('status' => 'success', 'message' => success_message,
                                  'archived' => final_state)
      expect(plan.reload.archived?).to eq(final_state)
    end

    it 'leaves another plan owned by the same user unchanged' do
      untouched = user.plans.create!(title: 'Another release', ident: 'release2',
                                     archived: initial_state)

      put action, params: { id: plan.ident }, format: :json

      expect(plan.reload.archived?).to eq(final_state)
      expect(untouched.reload.archived?).to eq(initial_state)
    end

    it 'reports a validation failure without persisting the archive status' do
      # Legacy invalid data can still be loaded by the controller.
      plan.update_column(:title, '')

      put action, params: { id: plan.ident }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json).to eq('status' => 'failed', 'message' => failure_message)
      expect(plan.reload.archived?).to eq(initial_state)
    end

    it 'reports a missing plan without changing existing plans' do
      put action, params: { id: 'missing-plan' }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json).to eq('status' => 'failed', 'alert' => '此计划不存在')
      expect(plan.reload.archived?).to eq(initial_state)
    end

    it 'does not accept a database id in place of the public ident' do
      put action, params: { id: plan.id.to_s }, format: :json

      expect(response_json).to eq('status' => 'failed', 'alert' => '此计划不存在')
      expect(plan.reload.archived?).to eq(initial_state)
    end

    it 'does not allow changing another user\'s plan' do
      foreign_plan = other_user.plans.create!(title: 'Private release', ident: 'private1',
                                             archived: initial_state)

      put action, params: { id: foreign_plan.ident }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json).to eq('status' => 'failed', 'alert' => '此计划不存在')
      expect(foreign_plan.reload.archived?).to eq(initial_state)
      expect(plan.reload.archived?).to eq(initial_state)
    end

    it 'requires authentication before changing a plan' do
      sign_out user

      put action, params: { id: plan.ident }, format: :json

      expect(response).to have_http_status(:unauthorized)
      expect(plan.reload.archived?).to eq(initial_state)
    end
  end

  describe 'PUT #archive as JSON' do
    include_examples 'a plan archive endpoint', :archive, false, true,
                     '计划已归档', '归档失败，请稍后重试 !'
  end

  describe 'PUT #unarchive as JSON' do
    include_examples 'a plan archive endpoint', :unarchive, true, false,
                     '计划已取消归档', '取消归档失败，请稍后重试 !'
  end

  describe 'GET #show as JSON' do
    [false, true].each do |archived|
      it "exposes the #{archived ? 'archived' : 'active'} status and member URLs using the public ident" do
        plan = user.plans.create!(title: 'Release', ident: 'release1', archived: archived)

        get :show, params: { id: plan.ident }, format: :json

        expect(response).to have_http_status(:ok)
        expect(response_json.fetch('archived')).to eq(archived)
        expect(response_json.fetch('archive_path')).to eq('/p/release1/archive.json')
        expect(response_json.fetch('unarchive_path')).to eq('/p/release1/unarchive.json')
      end
    end

    it 'keeps nested lists and tasks readable when their plan is archived' do
      plan = user.plans.create!(title: 'Release', ident: 'release1', archived: true)
      list = plan.lists.create!(title: 'Release tasks', user: user)
      task = plan.tasks.create!(title: 'Publish', list: list, user: user)

      get :show, params: { id: plan.ident }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response_json.fetch('archived')).to eq(true)
      expect(response_json.fetch('lists').map { |entry| entry.fetch('id') }).to eq([list.id])
      expect(response_json.fetch('lists').first.fetch('tasks').map { |entry| entry.fetch('id') })
        .to eq([task.id])
    end
  end
end
