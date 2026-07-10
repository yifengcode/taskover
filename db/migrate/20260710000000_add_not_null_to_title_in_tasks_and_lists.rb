class AddNotNullToTitleInTasksAndLists < ActiveRecord::Migration
  def up
    # Fill any existing NULL titles before adding NOT NULL constraint
    execute "UPDATE tasks SET title = '' WHERE title IS NULL"
    execute "UPDATE lists SET title = '' WHERE title IS NULL"

    change_column_null :tasks, :title, false
    change_column_null :lists, :title, false
  end

  def down
    change_column_null :tasks, :title, true
    change_column_null :lists, :title, true
  end
end
