class AddArchivedToPlans < ActiveRecord::Migration
  def change
    add_column :plans, :archived, :boolean, default: false, null: false
    add_index :plans, :archived
  end
end
