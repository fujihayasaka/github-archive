# typed: true
# frozen_string_literal: true

module Codespaces
  class TransferBillableOwner < Command
    attr_reader :codespace

    def initialize(codespace)
      @codespace = codespace
    end

    def perform
      # We want to delete the codespace if the owner no longer exists and can't transfer ownership
      # Deleting the codespace will happen separately. See Codespaces::ProcessSystemEvent
      return false if codespace.owner.nil?
      ActiveRecord::Base.connected_to(role: :writing) do
        new_billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(codespace.owner, codespace.repository).sync.billable_owner
        return false if new_billable_owner.nil?
        return false if codespace.billable_owner == new_billable_owner

        transfer(codespace, new_billable_owner)
      end
      true
    end

    private

    def transfer(codespace, new_billable_owner)
      old_billable_owner = codespace.billable_owner

      Codespaces::BillingEntry.transaction do
        new_billing_entry_values = codespace.billing_entry.attributes.slice(
          "codespace_owner_id", "codespace_owner_type", "codespace_guid",
          "codespace_plan_name", "codespace_created_at", "codespace_deleted_at",
          "codespace_deprovisioned_at", "repository_id", "copilot_workspace_id",
          "spark_workbench_id"
        ).merge(billable_owner: new_billable_owner)

        Codespaces::BillingEntry.create!(new_billing_entry_values)
        codespace.update!(billable_owner: new_billable_owner)
      end

      GitHub.instrument("codespaces.transfer_ownership",
        owner_id: codespace.owner_id,
        owner: codespace.owner.display_login,
        old_billable_owner_id: old_billable_owner.id,
        old_billable_owner_login: old_billable_owner&.display_login,
        new_billable_owner_id: new_billable_owner.id,
        new_billable_owner_login: new_billable_owner&.display_login,
        codespace_id: codespace.id,
        repo: codespace.repository,
        plan_id: codespace.plan_id,
        environment_id: codespace.guid
      )
    end
  end
end
