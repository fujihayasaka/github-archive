# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseUserAccount < Platform::Objects::Base
      implements Platform::Interfaces::AvatarOwner
      implements Platform::Interfaces::Actor

      model_name "BusinessUserAccount"
      description "An account for a user who is an admin of an enterprise or a member of an enterprise through one or more organizations."

      minimum_accepted_scopes ["read:enterprise"]

      implements_node templates: [[:eeua, :enterprise_id, :enterprise_user_account_id]], as: "EUA", ready_date: "2021-06-18" do |enterprise_user_account|
        {
          prefix: :eeua,
          enterprise_id: enterprise_user_account.business_id,
          enterprise_user_account_id: enterprise_user_account.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_business.then do |business|
          permission.access_allowed?(
            :site_admin_authorization,
            permission: :read_enterprise_members,
            resource: business,
            repo: nil,
            organization: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_business.then do |business|
          business.actor_can_read_members?(permission.viewer) || permission.viewer&.site_admin? || (business.member?(permission.viewer) && !object.spammy?)
        end
      end

      created_at_field
      updated_at_field

      field :user, Objects::User, description: "The user within the enterprise.", null: true, method: :async_user
      field :enterprise, Objects::Enterprise, description: "The enterprise in which this user account exists.", null: false, method: :async_business

      field :login, String, description: "An identifier for the enterprise user account, a login or email address", null: false
      field :name, String, description: "The name of the enterprise user account", null: true
      def name
        Promise.all([
          object.async_user,
          object.async_enterprise_installation_user_accounts,
        ]).then do |user, _|
          next object.name if user.nil?
          user.async_profile.then do |_profile|
            object.name
          end
        end
      end

      url_fields description: "The HTTP URL for this user." do |business_user_account|
        Promise.all([
          business_user_account.async_user,
          business_user_account.async_business,
        ]).then do |_user, business|
          if business_user_account.user
            business_user_account.user.permalink(include_host: false)
          else
            template = Addressable::Template.new("/enterprises/{slug}/enterprise_user_accounts/{id}")
            template.expand slug: business.slug, id: business_user_account.id
          end
        end
      end

      field :avatar_url, Scalars::URI, description: "A URL pointing to the enterprise user account's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(size: nil)
        # EnterpriseUserAccounts with no User won't be able to build avatar_urls. for now the template will handle that.
        object.async_user.then { object&.avatar_url(size) || "" }
      end

      field :organizations, resolver: Resolvers::EnterpriseOrganizationMemberships, description: "A list of enterprise organizations this user is a member of.", connection: true
      field :enterprise_installations, resolver: Resolvers::EnterpriseServerInstallationMemberships, description: "A list of Enterprise Server installations this user is a member of.", connection: true
    end
  end
end
