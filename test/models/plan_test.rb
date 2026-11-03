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
#  archived    :boolean          default(false), not null
#

require 'test_helper'

class PlanTest < ActiveSupport::TestCase
  setup do
    @plan = plans(:one)
  end

  test "new plan is not archived by default" do
    assert_not @plan.archived?
  end

  test "archive! sets archived to true" do
    assert @plan.archive!
    assert @plan.archived?
  end

  test "unarchive! sets archived to false" do
    @plan.archive!
    assert @plan.unarchive!
    assert_not @plan.archived?
  end

  test "active scope excludes archived plans" do
    @plan.archive!
    assert_not Plan.active.include?(@plan)
  end

  test "archived_only scope only includes archived plans" do
    @plan.archive!
    assert Plan.archived_only.include?(@plan)
  end
end
