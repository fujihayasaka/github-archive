class AddRepoIndex < ActiveRecord::Migration[5.0]
  def up
    # Based on the comment in lib/tasks/transitions.rake
    # this class no longer exists and causes a failure when running
    # migrations
    # Ingest::RepoIndex::Repository.reset_table
  end

  def down
    # no op
  end
end
