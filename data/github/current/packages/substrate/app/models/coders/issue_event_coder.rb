# typed: true
# frozen_string_literal: true

module Coders
  class IssueEventCoder < Coders::Base
    data_accessors \
      :after_commit_oid,
      :before_commit_oid,
      :card_id,
      :column_name,
      :deployment_id,
      :deployment_status_id,
      :label_id,
      :label_name,
      :label_color,
      :label_text_color,
      :lock_reason,
      :message,
      :milestone_id,
      :milestone_title,
      :performed_by_project_workflow_action_id,
      :previous_column_name,
      :pull_request_review_id,
      :pull_request_review_state_was,
      :ref,
      :review_request_id,
      :state_reason,
      :subject_id,
      :subject_type,
      :title_is,
      :title_was
  end
end
