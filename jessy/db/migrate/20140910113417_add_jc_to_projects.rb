class AddJcToProjects < ActiveRecord::Migration
  def change
    add_column :projects, :jc_host, :string
  end
end
