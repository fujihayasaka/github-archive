# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateAttributionInvitation < Platform::Mutations::Base
      description "Invites a user to claim reattributable data"

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

        invitation = AttributionInvitation.new(owner: owner, source: source, target: target, creator: context[:viewer])

        if invitation.save
          {
            owner: owner,
            source: source,
            target: target,
          }
        else
          raise Errors::Unprocessable.new(invitation.errors.full_messages.join(", "))
        end
      end
    end
  end
end
