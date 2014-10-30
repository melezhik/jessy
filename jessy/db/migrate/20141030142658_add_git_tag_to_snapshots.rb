class AddGitTagToSnapshots < ActiveRecord::Migration
  def change
    add_column :snapshots, :git_tag, :string
  end
end
