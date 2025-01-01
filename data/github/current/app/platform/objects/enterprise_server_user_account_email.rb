# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseServerUserAccountEmail < Platform::Objects::Base
      model_name "EnterpriseInstallationUserAccountEmail"
      description "An email belonging to a user account on an Enterprise Server installation."

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
      def self.async_viewer_can_see?(permission, enterprise_server_user_account_email)
        return false if permission.viewer.nil?
        return true if permission.viewer.site_admin?

        enterprise_server_user_account_email.async_enterprise_installation_user_account.then do |user_account|
          permission.typed_can_see?("EnterpriseServerUserAccount", user_account)
        end
      end

      implements_node templates: [
        [:eesua, :enterprise_id, :enterprise_server_user_account_email_id],
        [:uesua, :user_id, :enterprise_server_user_account_email_id],
        [:oesua, :organization_id, :enterprise_server_user_account_email_id],
      ], as: "ESUAE", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |enterprise_server_user_account_email|
        enterprise_server_user_account_email.async_enterprise_installation_user_account.then do |user_account|
          user_account.async_enterprise_installation.then do |installation|
            case installation.owner_type
            when "Business"
              {
                prefix: :eesua,
                enterprise_id: installation.owner_id,
                enterprise_server_user_account_email_id: enterprise_server_user_account_email.id,
              }
            when "User"
              # Owners can be organizations here,
              # but it's written as `"User"` in the `owner_type` column
              installation.async_owner.then do |owner|
                case owner
                when ::Organization
                  {
                    prefix: :oesua,
                    organization_id: owner.id,
                    enterprise_server_user_account_email_id: enterprise_server_user_account_email.id,
                  }
                else
                  {
                    prefix: :uesua,
                    user_id: owner.id,
                    enterprise_server_user_account_email_id: enterprise_server_user_account_email.id,
                  }
                end
              end
            else
              raise Platform::Errors::Internal, "Unexpected installation owner type: #{installation.owner_type.inspect}"
            end
          end
        end
      end

      created_at_field
      updated_at_field

      field :user_account, Objects::EnterpriseServerUserAccount,
        description: "The user account to which the email belongs.",
        null: false, method: :async_enterprise_installation_user_account
      field :email, String, description: "The email address.", null: false
      field :is_primary, Boolean,
        description: "Indicates whether this is the primary email of the associated user account.",
        method: :primary?, null: false
    end
  end
end
