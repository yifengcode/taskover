# == Schema Information
#
# Table name: tasks
#
#  id          :integer          not null, primary key
#  title       :text(65535)
#  description :text(65535)
#  status      :integer          default(1)
#  list_id     :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  plan_id     :integer
#  user_id     :integer          not null
#

class Task < ActiveRecord::Base

  STATUS_CLOSED = 0
  STATUS_OPEN = 1

  belongs_to :plan
  belongs_to :list
  belongs_to :user

  validates :title, presence: true
  validates :list,  presence: true
  validates :plan,  presence: true
  validates :user,  presence: true

  after_create :add_sort
  after_destroy :delete_sort


  def closed?
    status == STATUS_CLOSED
  end

  def opened?
    status == STATUS_OPEN
  end

  def add_sort
    task_sort = list.task_sort
    if task_sort.nil?
      task_sort = list.build_task_sort
      task_sort.sort = list.tasks.pluck(:id)
    else
      task_sort.sort.unshift(id)
    end
    task_sort.save
  end

  def delete_sort
    task_sort = list.task_sort
    if task_sort.present?
      task_sort.sort.delete(id)
      task_sort.save
    end
  end

end
