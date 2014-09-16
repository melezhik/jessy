class AddForceModeToProjects < ActiveRecord::Migration
  def change
    add_column :projects, :force_mode, :boolean
  end
end
