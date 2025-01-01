# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseServerInstallation < Platform::Objects::Base
      implements_node templates: [[:u, :user_id, :id], [:b, :business_id, :id]], as: "ESI", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |esi|
        case esi.owner_type
        when "User"
          {
            prefix: :u,
            user_id: esi.owner_id,
            id: esi.id,
          }
        when "Business"
          {
            prefix: :b,
            business_id: esi.owner_id,
            id: esi.id,
          }
        else
          raise Platform::Errors::Internal, "Unexpected project owner_type: #{esi.owner_type.inspect}"
        end
      end

      model_name "EnterpriseInstallation"
      description "An Enterprise Server installation."

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
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer&.site_admin?

        object.async_owner.then do |owner|
          permission.can_list_enterprise_installations?(owner)
        end
      end

      created_at_field
      updated_at_field

      field :host_name, String, description: "The host name of the Enterprise Server installation.", null: false
      field :customer_name, String, description: "The customer name to which the Enterprise Server installation belongs.", null: false
      field :is_connected, Boolean, method: :connected?, description: "Whether or not the installation is connected to an Enterprise Server installation via GitHub Connect.", null: false
      field :user_accounts, resolver: Resolvers::EnterpriseServerUserAccounts, description: "User accounts on this Enterprise Server installation.", connection: true
      field :user_accounts_uploads, resolver: Resolvers::EnterpriseServerUserAccountsUploads,
        description: "User accounts uploads for the Enterprise Server installation.", connection: true
    end
  end
end
