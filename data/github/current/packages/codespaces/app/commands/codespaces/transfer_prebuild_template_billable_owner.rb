# typed: true
# frozen_string_literal: true

module Codespaces
  class TransferPrebuildTemplateBillableOwner < Command
    attr_reader :latest_billing_entry

    def initialize(prebuild_template_guid)
      @latest_billing_entry = PrebuildTemplateBillingEntry.latest(prebuild_template_guid)
    end

    def perform
      return false unless latest_billing_entry && latest_billing_entry.prebuild_deleted_at.nil?

      new_billable_owner = latest_billing_entry.repository&.owner

      # If the repo or owner is not found (ie deleted) we can't transfer ownership
      # We'll be handling deleted prebuild-enabled repos here: https://github.com/github/codespaces/issues/7498
      return false if new_billable_owner.nil?

      return false if latest_billing_entry.billable_owner == new_billable_owner

      transfer(new_billable_owner)
      true
    end

    private

    def transfer(new_billable_owner)
      old_billable_owner = latest_billing_entry.billable_owner

      new_billing_entry = T.let(nil, T.nilable(PrebuildTemplateBillingEntry))
      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::PrebuildTemplateBillingEntry.transaction do
          new_billing_entry_values = T.let(
            latest_billing_entry.attributes.slice(
              "prebuild_template_guid", "prebuild_template_plan_name", "prebuild_template_created_at",
              "prebuild_template_deleted_at", "repository_id"
            ).merge(billable_owner: new_billable_owner),
            T::Hash[String, T.untyped]
          )


          new_billing_entry = Codespaces::PrebuildTemplateBillingEntry.create!(new_billing_entry_values)
        end
      end

      GitHub.instrument("codespaces.prebuild_template_transfer_ownership",
        old_billable_owner_id: old_billable_owner.id,
        old_billable_owner_login: old_billable_owner&.display_login,
        new_billable_owner_id: new_billable_owner.id,
        new_billable_owner_login: new_billable_owner&.display_login,
        plan_name: new_billing_entry&.prebuild_plan_name,
        environment_id: new_billing_entry&.prebuild_template_guid
      )
    end
  end
end
