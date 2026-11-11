# typed: true
# frozen_string_literal: true

class AddRequiredReasonType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :review_request_reasons, bulk: :true do |t|
      t.change :reason_type, "enum('codeowners','copilot','copilot_org_setting','copilot_repo_setting','copilot_user_setting','required_by_rule')", null: true
    end

    change_table :archived_review_request_reasons, bulk: :true do |t|
      t.change :reason_type, "enum('codeowners','copilot','copilot_org_setting','copilot_repo_setting','copilot_user_setting','required_by_rule')", null: true
    end
  end

  def down
    change_table :review_request_reasons, bulk: :true do |t|
      t.change :reason_type, "enum('codeowners','copilot','copilot_org_setting','copilot_repo_setting','copilot_user_setting')", null: true
    end

    change_table :archived_review_request_reasons, bulk: :true do |t|
      t.change :reason_type, "enum('codeowners','copilot','copilot_org_setting','copilot_repo_setting','copilot_user_setting')", null: true
    end
  end
end
