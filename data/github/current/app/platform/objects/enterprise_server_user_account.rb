# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseServerUserAccount < Platform::Objects::Base
      implements_node templates: [[:esua, :enterprise_installation_id, :id]], as: "ESUA", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |esua|
        { prefix: :esua, enterprise_installation_id: esua.enterprise_installation_id, id: esua.id }
      end

      model_name "EnterpriseInstallationUserAccount"
      description "A user account on an Enterprise Server installation."

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_target_for_conditional_access.then do |tfca|
          permission.access_allowed?(:enterprise_installation, resource: object,
            current_repo: nil, current_org: nil, tfca: tfca,
            allow_integrations: true, allow_user_via_granular_actor: false)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, enterprise_server_user_account)
        return false if permission.viewer.nil?
        return true if permission.viewer.site_admin?

        enterprise_server_user_account.async_enterprise_installation.then do |enterprise_installation|
          permission.typed_can_see?("EnterpriseServerInstallation", enterprise_installation)
        end
      end

      created_at_field
      updated_at_field

      field :enterprise_server_installation, Objects::EnterpriseServerInstallation,
        description: "The Enterprise Server installation on which this user account exists.",
        null: false, method: :async_enterprise_installation
      field :remote_user_id, Integer, description: "The ID of the user account on the Enterprise Server installation.", null: false
      field :remote_created_at, Scalars::DateTime, description: "The date and time when the user account was created on the Enterprise Server installation.", null: false
      field :login, String, description: "The login of the user account on the Enterprise Server installation.", null: false
      field :profile_name, String, description: "The profile name of the user account on the Enterprise Server installation.", null: true
      field :is_site_admin, Boolean, description: "Whether the user account is a site administrator on the Enterprise Server installation.", method: :site_admin?, null: false
      field :emails, resolver: Resolvers::EnterpriseServerUserAccountEmails, description: "User emails belonging to this user account.", connection: true
    end
  end
end
