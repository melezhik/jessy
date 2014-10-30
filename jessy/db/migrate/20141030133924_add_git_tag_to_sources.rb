class AddGitTagToSources < ActiveRecord::Migration
  def change
    add_column :sources, :git_tag, :string
  end
end
