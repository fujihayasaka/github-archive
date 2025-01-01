# typed: true
# frozen_string_literal: true

module Codespaces
  class BillingEntry < ApplicationRecord::Domain::Codespaces
    include Instrumentation::Model

    self.table_name = "codespace_billing_entries"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :codespace, foreign_key: :codespace_guid, primary_key: :guid, strict_loading: false
    # rubocop:enable Rails/InverseOf
    belongs_to :billable_owner, polymorphic: true, strict_loading: false
    belongs_to :codespace_owner, polymorphic: true, strict_loading: false
    belongs_to :repository, class_name: "::Repository", strict_loading: false

    validates :billable_owner, :codespace_owner, :codespace_guid, :codespace_plan_name, presence: true

    def self.latest(codespace_guid)
      where(codespace_guid: codespace_guid).last
    end

    def self.latest_created_before(codespace_guid, created_before)
      where(codespace_guid: codespace_guid).where("created_at <= ?", created_before).last
    end

    def for_prebuild?
      false
    end

    # Duplicating these methods from Codespace because there's no guarantee a BillingEntry will still have a valid Codespace relationship...
    def for_codespace?
      copilot_workspace_id.blank?
    end

    def for_copilot_workspace?
      copilot_workspace_id.present? && !for_workspace_editor?
    end

    def for_workspace_editor?
      copilot_workspace_id == WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID
    end
  end
end
