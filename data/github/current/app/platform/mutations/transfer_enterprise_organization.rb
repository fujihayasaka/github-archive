# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class TransferEnterpriseOrganization < Platform::Mutations::Base
      description "Transfer an organization from one enterprise to another enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :organization_id, ID,
        "The ID of the organization to transfer.",
        required: true, loads: Objects::Organization
      argument :destination_enterprise_id, ID,
        "The ID of the enterprise where the organization should be transferred.",
        required: true, loads: Objects::Enterprise

      field :organization, Objects::Organization, "The organization for which a transfer was initiated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        permission.access_allowed? \
          :administer_business,
          resource: organization.business,
          repo: nil,
          organization: organization,
          allow_integrations: false,
          allow_user_via_granular_actor: false
      end

      def resolve(organization:, destination_enterprise:, **inputs)
        ensure_business_can_use_api!(organization.business)
        business_full_plan_required!(organization.business)

        viewer = context[:viewer]

        if GitHub.single_business_environment?
          raise Errors::Unprocessable.new("Enterprise organization transfers are disabled in this environment.")
        end

        transfer = BusinessOrganizationTransfer.create \
          organization: organization,
          from_business: organization.business,
          to_business: destination_enterprise,
          actor: viewer
        if transfer.valid?
          BusinessOrganizationTransferJob.perform_later(transfer)
        else
          raise Errors::Unprocessable.new transfer.errors.full_messages.first
        end

        { organization: organization }
      end
    end
  end
end
