# == Schema Information
#
# Table name: plans
#
#  id          :integer          not null, primary key
#  title       :text(65535)
#  description :text(65535)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  color_tag   :integer          default(0)
#  ident       :string(255)      not null
#  user_id     :integer          not null
#

require 'rails_helper'

RSpec.describe Plan, type: :model do
  # rails_helper truncates before each example, which commits MySQL transactions.
  self.use_transactional_tests = false

  let(:user) do
    User.create!(ident: 'archive-owner', email: 'archive-owner@example.com',
                 password: 'password123', confirmed_at: Time.current)
  end
  let(:plan) do
    user.plans.create!(title: 'Release', description: 'Prepare a release',
                       ident: 'release1', color_tag: Plan::COLOR_TAG['blue'])
  end

  describe 'archive defaults' do
    it 'starts a new plan with a false boolean archive status' do
      expect(described_class.new.archived?).to eq(false)
    end

    it 'persists the database default for a newly created plan' do
      expect(plan.reload.archived?).to eq(false)
      expect(described_class.active).to include(plan)
      expect(described_class.archived_only).not_to include(plan)
    end

    it 'rejects a null archive status at the database boundary' do
      expect { plan.update_column(:archived, nil) }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect(plan.reload.archived?).to eq(false)
    end
  end

  shared_examples 'a persistent archive transition' do |method, initial_state, final_state|
    before { plan.update!(archived: initial_state) }

    it 'returns true and persists the requested status' do
      expect(plan.public_send(method)).to eq(true)
      expect(plan.reload.archived?).to eq(final_state)
    end

    it 'can be repeated without creating or deleting plans' do
      expect do
        2.times { expect(plan.public_send(method)).to eq(true) }
      end.not_to change(described_class, :count)
      expect(plan.reload.archived?).to eq(final_state)
    end

    it 'returns false without persisting the transition when validation fails' do
      plan.title = ''

      expect(plan.public_send(method)).to eq(false)
      expect(plan.errors[:title]).not_to be_empty
      expect(plan.reload.archived?).to eq(initial_state)
      expect(plan.title).to eq('Release')
    end
  end

  describe '#archive!' do
    include_examples 'a persistent archive transition', :archive!, false, true
  end

  describe '#unarchive!' do
    include_examples 'a persistent archive transition', :unarchive!, true, false
  end

  describe 'archive scopes' do
    let!(:active_plan) { plan }
    let!(:archived_plan) do
      user.plans.create!(title: 'Archived release', ident: 'release2', archived: true,
                         color_tag: Plan::COLOR_TAG['green'])
    end

    it 'returns exactly the active plans' do
      expect(described_class.active).to contain_exactly(active_plan)
    end

    it 'returns exactly the archived plans' do
      expect(described_class.archived_only).to contain_exactly(archived_plan)
    end

    it 'moves a plan between scopes after archiving and unarchiving' do
      expect(active_plan.archive!).to eq(true)
      expect(described_class.active).to be_empty
      expect(described_class.archived_only).to contain_exactly(active_plan, archived_plan)

      expect(active_plan.unarchive!).to eq(true)
      expect(described_class.active).to contain_exactly(active_plan)
      expect(described_class.archived_only).to contain_exactly(archived_plan)
    end

    it 'composes with the existing color filter' do
      expect(described_class.active.with_color_tag(Plan::COLOR_TAG['blue']))
        .to contain_exactly(active_plan)
      expect(described_class.archived_only.with_color_tag(Plan::COLOR_TAG['blue']))
        .to be_empty
      expect(described_class.with_color_tag(Plan::COLOR_TAG['green']).archived_only)
        .to contain_exactly(archived_plan)
    end

    it 'preserves user scoping for both active and archived plans' do
      other_user = User.create!(ident: 'other-owner', email: 'other-owner@example.com',
                                password: 'password123', confirmed_at: Time.current)
      other_user.plans.create!(title: 'Other active', ident: 'other001')
      other_user.plans.create!(title: 'Other archived', ident: 'other002', archived: true)

      expect(user.plans.active).to contain_exactly(active_plan)
      expect(user.plans.archived_only).to contain_exactly(archived_plan)
    end
  end

  it 'preserves plan details, nested content, and saved ordering through an archive round trip' do
    list = plan.lists.create!(title: 'Release tasks', user: user)
    task = plan.tasks.create!(title: 'Publish', list: list, user: user)
    original_details = plan.attributes.slice('title', 'description', 'ident', 'color_tag', 'user_id')
    original_plan_sort = user.plan_sort.reload.sort.dup
    original_list_sort = plan.list_sort.reload.sort.dup
    original_task_sort = list.task_sort.reload.sort.dup

    [true, false].each do |archived|
      expect(plan.public_send(archived ? :archive! : :unarchive!)).to eq(true)
      expect(plan.reload.attributes.slice(*original_details.keys)).to eq(original_details)
      expect(plan.lists).to contain_exactly(list)
      expect(plan.tasks).to contain_exactly(task)
      expect(user.plan_sort.reload.sort).to eq(original_plan_sort)
      expect(plan.list_sort.reload.sort).to eq(original_list_sort)
      expect(list.task_sort.reload.sort).to eq(original_task_sort)
    end
  end
end
