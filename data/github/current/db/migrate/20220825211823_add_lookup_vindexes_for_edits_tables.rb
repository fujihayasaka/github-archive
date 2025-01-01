# typed: true
# rubocop:disable GitHub/OneTablePerMigration
# rubocop:disable GitHub/SpecifyDefaultCharsetAndCollation
class AddLookupVindexesForEditsTables < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :commit_comment_edits_on_user_content_edit_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :user_content_edit_id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :commit_comment_edits_on_user_content_edit_id_ks_idx, :hash, :user_content_edit_id

    create_vindex :commit_comment_edits_on_user_content_edit_id_ks_idx, :lookup_unique, owner: "commit_comment_edits", from: "user_content_edit_id", table: "commit_comment_edits_on_user_content_edit_id_ks_idx", to: "keyspace_id", ignore_nulls: true
    add_vindex :commit_comment_edits, :commit_comment_edits_on_user_content_edit_id_ks_idx, :user_content_edit_id

    create_table :issue_comment_edits_on_user_content_edit_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :user_content_edit_id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comment_edits_on_user_content_edit_id_ks_idx, :hash, :user_content_edit_id

    create_vindex :issue_comment_edits_on_user_content_edit_id_ks_idx, :lookup_unique, owner: "issue_comment_edits", from: "user_content_edit_id", table: "issue_comment_edits_on_user_content_edit_id_ks_idx", to: "keyspace_id", ignore_nulls: true
    add_vindex :issue_comment_edits, :issue_comment_edits_on_user_content_edit_id_ks_idx, :user_content_edit_id

    create_table :issue_edits_on_user_content_edit_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :user_content_edit_id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_edits_on_user_content_edit_id_ks_idx, :hash, :user_content_edit_id

    create_vindex :issue_edits_on_user_content_edit_id_ks_idx, :lookup_unique, owner: "issue_edits", from: "user_content_edit_id", table: "issue_edits_on_user_content_edit_id_ks_idx", to: "keyspace_id", ignore_nulls: true
    add_vindex :issue_edits, :issue_edits_on_user_content_edit_id_ks_idx, :user_content_edit_id

    create_table :pull_request_review_comment_edits_on_user_content_edit_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :user_content_edit_id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_comment_edits_on_user_content_edit_id_ks_idx, :hash, :user_content_edit_id

    create_vindex :pull_request_review_comment_edits_on_user_content_edit_id_ks_idx, :lookup_unique, owner: "pull_request_review_comment_edits", from: "user_content_edit_id", table: "pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", to: "keyspace_id", ignore_nulls: true
    add_vindex :pull_request_review_comment_edits, :pull_request_review_comment_edits_on_user_content_edit_id_ks_idx, :user_content_edit_id

    create_table :pull_request_review_edits_on_user_content_edit_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :user_content_edit_id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_edits_on_user_content_edit_id_ks_idx, :hash, :user_content_edit_id

    create_vindex :pull_request_review_edits_on_user_content_edit_id_ks_idx, :lookup_unique, owner: "pull_request_review_edits", from: "user_content_edit_id", table: "pull_request_review_edits_on_user_content_edit_id_ks_idx", to: "keyspace_id", ignore_nulls: true
    add_vindex :pull_request_review_edits, :pull_request_review_edits_on_user_content_edit_id_ks_idx, :user_content_edit_id
  end
end
