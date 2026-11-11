# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseStafftoolsInfo < Platform::Objects::Base
      # Deliberately does not implement Interfaces::AccountStafftoolsInfo which contains a lot of user-centric logic
      description "Enterprise account information only visible to site admin"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :billing_email, String, description: "The enterprise billing email address.", null: true

      def billing_email
        @object.account.billing_email
      end

      field :is_downgraded_to_free_plan, Boolean, description: "Was the enterprise downgraded to free?", null: false

      def is_downgraded_to_free_plan
        @object.account.downgraded_to_free_plan?
      end

      field :is_trial_account, Boolean, description: "Is the enterprise on a trial?", null: false

      def is_trial_account
        @object.account.trial?
      end

      field :is_spammy, Boolean, description: "Is the account spammy?", null: false

      def is_spammy
        @object.account.spammy?
      end

      field :spammy_reason, String, description: "The spammy reason.", null: true

      def spammy_reason
        @object.account.spammy_reason
      end

      field :is_hammy, Boolean, description: "Is the account hammy?", null: false

      def is_hammy
        @object.account.hammy?
      end

      field :is_never_spammy, Boolean, description: "Can this account be marked as spammy?", null: false

      def is_never_spammy
        @object.account.never_spammy?
      end

      field :is_suspended, Boolean, description: "Is the account suspended?", null: false

      def is_suspended
        @object.account.suspended?
      end

      field :members, Connections.define(Unions::EnterpriseMember, edge_type: Edges::EnterpriseMember), description: "A list of users who are members of this enterprise.", null: false, connection: true do
        argument :order_by, Inputs::EnterpriseMemberOrder, "Ordering options for members returned from the connection.", required: false, default_value: { field: "login", direction: "ASC" }
        argument :organization_logins, [String], "Only return members within the organizations with these logins", required: false
      end

      def members(order_by: nil, organization_logins: nil)
        object.account.async_organizations.then do
          object.account.filtered_members \
            context[:viewer],
            ignore_org_membership_visibility: true,
            organization_logins: organization_logins,
            order_by_field: order_by&.dig(:field) || "login",
            order_by_direction: order_by&.dig(:direction) || "ASC"
        end
      end

      field :admins, resolver: Resolvers::EnterpriseAdmins, description: "A list of all of the administrators for this enterprise.", connection: true, exempt_from_spam_filter_check: true
    end
  end
end
