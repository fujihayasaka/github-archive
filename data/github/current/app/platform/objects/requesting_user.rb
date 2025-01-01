# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class RequestingUser < Platform::Objects::Base
      include Helpers::Newsies
      include Helpers::ConditionalAccess

      description "The currently authenticated user making the request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, requesting_user)
        permission.access_allowed?(:v4_read_user_private, user: permission.viewer, resource: requesting_user.user, current_repo: nil, current_org: nil, allow_integration: false, allow_user_via_granular_actor: false, allow_integrations: false)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.user == permission.viewer
      end

      visibility :under_development

      minimum_accepted_scopes ["read:user"]

      field :user, Objects::User, description: "The underlying user object.", null: true, method: :user

      field :plan, Objects::Plan, description: "The current user's billing plan.", null: true, method: :async_plan

      field :teams, Connections.define(Objects::Team), visibility: :internal, description: "A list of the teams the current viewer belongs to across organizations.", null: false, connection: true do
        argument :order_by, Inputs::TeamOrder, "Ordering options for teams returned from the connection", required: false
      end

      def teams(**arguments)
        # Join to organizations so we exclude teams whose organizations have been deleted:
        scope = @object.teams.joins(:organization)

        if arguments[:order_by]
          order = "#{arguments[:order_by][:field]} #{arguments[:order_by][:direction]}"
          scope = scope.order(order)
        end
        scope
      end

      field :adminable_apps, Connections.define(Objects::App), visibility: :internal, description: "A list of GitHub Apps managed by this user.", null: false, connection: true do
        argument :exclude_marketplace_listings, Boolean, <<~DESCRIPTION, required: false
            Filters apps to exclude those that have a Marketplace listing. If omitted,
            integrations that are in the Marketplace will be included.
          DESCRIPTION
        argument :public_only, Boolean, <<~DESCRIPTION, required: false
            Filters apps so only public apps are returned. If omitted or false, both
            public and internal apps will be returned.
          DESCRIPTION
      end

      def adminable_apps(**arguments)
        scope = ::Integration.adminable_by(@object.user)
        scope = scope.not_in_marketplace if arguments[:exclude_marketplace_listings]
        scope = scope.public if arguments[:public_only]
        scope = scope.where.not(owner_id: @context[:unauthorized_organization_ids])
        scope.order("integrations.updated_at DESC")
      end
    end
  end
end
