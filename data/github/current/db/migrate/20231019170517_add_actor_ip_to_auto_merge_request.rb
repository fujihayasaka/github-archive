class AddActorIpToAutoMergeRequest < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    add_column :auto_merge_requests, :actor_ip_address, "varchar(40)", null: true
  end
end
