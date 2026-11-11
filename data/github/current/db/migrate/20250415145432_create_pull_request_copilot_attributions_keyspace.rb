# typed: true
# frozen_string_literal: true

class CreatePullRequestCopilotAttributionsKeyspace < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :pull_request_copilot_attributions_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_copilot_attributions_id_ks_idx, :hash, :id
    create_vindex :pull_request_copilot_attributions_id_ks_idx, :lookup_unique, owner: "pull_request_copilot_attributions", from: "id", table: "pull_request_copilot_attributions_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"
    add_vindex :pull_request_copilot_attributions, :pull_request_copilot_attributions_id_ks_idx, :id
  end
end
