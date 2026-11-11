# typed: true
# frozen_string_literal: true

module Codespaces
  class UsageRecord < ApplicationRecord::Domain::Codespaces
    include Codespaces::LinkedResourcesDependency

    self.table_name = "codespace_usage_records"

    belongs_to :owner, polymorphic: true, strict_loading: false
    belongs_to :billable_owner, polymorphic: true, strict_loading: false

    scope :for_copilot_workspaces, -> { not_spark_workbenches.where.not(copilot_workspace_id: [nil, WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID]) }
    # extracts spark_id from JSON string linked_resources
    scope :for_spark_workbenches, -> {
      where.not(linked_resources: nil)
      .where("linked_resources->'$.spark_workbench_id' IS NOT NULL")
    }
    scope :not_spark_workbenches, -> { where("linked_resources->'$.spark_workbench_id' IS NULL") }

    scope :for_workspace_editor, -> { where(copilot_workspace_id: WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID) }
    scope :current, -> { where(start_at: DateTime.current.beginning_of_month..) }

    validates :owner, :billable_owner, :start_at, :end_at, presence: true
    validates :codespace_guid, length: { is: 36 }
    validates :copilot_workspace_id, length: { maximum: 36 }, allow_nil: true
    validates :usage_seconds, numericality: { only_integer: true }
  end
end
