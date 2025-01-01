# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseServerUserAccountsUpload < Platform::Objects::Base
      model_name "EnterpriseInstallationUserAccountsUpload"
      description "A user accounts upload from an Enterprise Server installation."

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_business.then do |business|
          permission.access_allowed?(:administer_business, resource: business,
            organization: nil, repo: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer&.site_admin?

        object.async_business.then do |business|
          business.owner? permission.viewer
        end
      end

      implements_node templates: [
          [:eesuau, :enterprise_id, :enterprise_server_user_accounts_upload_id]
        ], as: "ESUAU", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |enterprise_server_user_accounts_upload|
        {
          prefix: :eesuau,
          enterprise_id: enterprise_server_user_accounts_upload.business_id,
          enterprise_server_user_accounts_upload_id: enterprise_server_user_accounts_upload.id,
        }
      end

      created_at_field
      updated_at_field

      field :enterprise, Objects::Enterprise,
        description: "The enterprise to which this upload belongs.",
        null: false, method: :async_business
      field :enterprise_server_installation, Objects::EnterpriseServerInstallation,
        description: "The Enterprise Server installation for which this upload was generated.",
        null: false, method: :async_enterprise_installation
      field :name, String, description: "The name of the file uploaded.", null: false
      field :sync_state, Enums::EnterpriseServerUserAccountsUploadSyncState,
        description: "The synchronization state of the upload", null: false
    end
  end
end
