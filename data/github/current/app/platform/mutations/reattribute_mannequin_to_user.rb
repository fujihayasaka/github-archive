# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReattributeMannequinToUser < Platform::Mutations::Base
      description "Reattributes data linked to a mannequin to a user. This mutation only supports [Enterprise Managed Users](https://docs.github.com/enterprise-cloud@latest/admin/identity-and-access-management/using-enterprise-managed-users-for-iam/about-enterprise-managed-users). If you are not using Enterprise Managed Users, then you can reattribute data linked to mannequins using the `createAttributionInvitation` mutation."

      feature_flag :mannequin_claiming_emu
      minimum_accepted_scopes ["admin:org"]

      argument :owner_id, ID, "The Node ID of the owner scoping the reattributable data.", required: true, loads: Unions::Account
      argument :source_id, ID, "The Node ID of the account owning the data to reattribute.", required: true, loads: Unions::Account
      argument :target_id, ID, "The Node ID of the account which may claim the data.", required: true, loads: Unions::Account

      field :owner, Objects::Organization, "The owner scoping the reattributable data.", null: true
      field :source, Unions::Claimable, "The account owning the data to reattribute.", null: true
      field :target, Unions::Claimable, "The account which may claim the data.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        permission.access_allowed?(:migration_import, resource: owner, organization: owner, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(owner:, source:, target:)
        unless owner.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to reattribute data in #{owner.display_login}.")
        end

        unless owner.enterprise_managed_user_enabled?
          raise Errors::Unprocessable.new("#{owner.display_login} is not an Enterprise Managed Users (EMU) organization. To reattribute mannequins, please use the `createAttributionInvitation` mutation.")
        end

        invitation = AttributionInvitation.new(owner: owner, source: source, target: target, creator: context[:viewer], bypass_email: true)

        raise Errors::Unprocessable.new(invitation.errors.full_messages.join(", ")) unless invitation.save

        begin
          invitation.accept!
          {
            owner: owner,
            source: source,
            target: target
          }
        rescue Workflow::NoTransitionAllowed
          raise Errors::Unprocessable.new("Could not accept invitation for reattributing #{source.display_login} to #{target.display_login} in #{owner.display_login}.")
        end
      end
    end
  end
end
