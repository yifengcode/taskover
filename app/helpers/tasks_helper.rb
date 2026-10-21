module TasksHelper
  # 任务状态对应的展示文案
  def task_status_label(task)
    task.closed? ? '已完成' : '进行中'
  end

  # 返回任务状态对应的样式类名，供列表视图使用
  def task_status_class(task)
    task.closed? ? 'task-done' : 'task-pending'
  end

  # 展示任务所属人名称，复用 User#display_name
  def task_owner_name(task)
    task.user&.display_name
  end
end
