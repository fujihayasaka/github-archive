# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ExternalIdentity < Platform::Objects::Base
      description "An external identity provisioned by SAML SSO or SCIM. If SAML is configured on the organization,
        the external identity is visible to (1) organization owners, (2) organization owners' personal access tokens (classic) with read:org or admin:org scope,
        (3) GitHub App with an installation token with read or write access to members. If SAML is configured on the enterprise,
        the external identity is visible to (1) enterprise owners, (2) enterprise owners' personal access tokens (classic) with read:enterprise or admin:enterprise scope.".squish

      implements_node templates: [[:eipei, :enterprise_id, :enterprise_identity_provider_id, :external_identity_id], [:oipei, :org_id, :org_identity_provider_id, :external_identity_id]], as: "EI", ready_date: "2021-07-02" do |external_identity|
        external_identity.async_provider.then do |provider|
          case external_identity.provider_type
          when "Business::SamlProvider"
            {
              prefix: :eipei,
              enterprise_id: provider.business_id,
              enterprise_identity_provider_id: provider.id,
              external_identity_id: external_identity.id
            }
          when "Organization::SamlProvider"
            {
              prefix: :oipei,
              org_id: provider.organization_id,
              org_identity_provider_id: provider.id,
              external_identity_id: external_identity.id
            }
          else
            raise Platform::Errors::Internal, "Unexpected identity provider: #{provider.inspect}"
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, external_identity)
        external_identity.async_provider.then do |provider|
          provider.async_target.then do |target|
            case target
            when ::Organization
              permission.access_allowed?(:view_org_external_identities, resource: target, organization: target, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
            when ::Business
              if ::FeatureFlag.vexi.enabled?(:bypass_permission_check_for_team_sync_enterprise, target, default: false)
                next true if permission.access_allowed?(:v4_view_enterprise_external_identities, resource: target, organization: nil, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
              else
                if GitHub.enterprise?
                  next true if permission.access_allowed?(:view_enterprise_external_identities_read_only, resource: target, organization: nil, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
                else
                  next true if permission.access_allowed?(
                    :site_admin_authorization,
                    permission: :read_enterprise_scim,
                    resource: target,
                    organization: nil,
                    current_repo: nil,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    raise_on_error: false
                  )

                  next true if permission.access_allowed?(
                    :site_admin_authorization,
                    permission: :read_enterprise_sso,
                    resource: target,
                    organization: nil,
                    current_repo: nil,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    raise_on_error: false
                  )
                end
              end

              start_time = Time.now
              check_user_access(permission, external_identity, target).then do |result|
                end_time = Time.now
                duration = end_time - start_time

                GitHub.logger.info(
                  "info.message" => "Check user access for external identity",
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "gh.duration" => "#{duration}s",
                  "gh.business.slug" => target.slug,
                  "gh.business.id" => target.id,
                  "gh.external_identity" => external_identity.id,
                  "gh.permission" => permission.viewer.id
                )

                result
              end
            else
              false
            end
          end
        end
      end

      def self.results_match?(original_result, candidate_result)
        original_result == candidate_result
      end

      def self.check_user_access(permission, external_identity, target)
        external_identity.async_user.then do |user|
          user.async_organization_ids.then do |org_ids|
            next Promise.resolve(false) if org_ids.empty?

            # Get orgs with an associated biz
            Platform::Loaders::BusinessOrganizations.load(target, org_ids).then do |business_orgs|
              next Promise.resolve(false) if business_orgs.empty?

              access_allowed = business_orgs.any? do |org|
                permission.access_allowed?(:v4_manage_org_users, resource: org, organization: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
              end

              Promise.resolve(access_allowed)
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer.site_admin?

        object.async_provider.then do |provider|
          provider.async_target.then do |target|
            target.async_adminable_by?(permission.viewer).then do |adminable|
              next true if adminable

              case target
              when ::Organization
                next false unless permission.viewer.try(:installation)
                next true if target.resources.members.readable_by?(permission.viewer)
                next true if target.resources.organization_administration.readable_by?(permission.viewer)
                false
              when ::Business
                unless GitHub.enterprise?
                  next true if Authz.domain.check_multiple_permissions(permission.viewer, [:read_enterprise_sso, :read_enterprise_scim], target).values.any?
                end
                next false unless permission.viewer.try(:installation)

                target.async_organizations.then do |orgs|
                  orgs.any? { |org| org.resources.members.readable_by?(permission.viewer) }
                end
              else
                false
              end
            end
          end
        end
      end

      minimum_accepted_scopes ["read:org", "read:enterprise", "scim:enterprise"]

      field :guid, String, "The GUID for this identity", null: false

      field :saml_identity, Objects::ExternalIdentitySamlAttributes, description: "SAML Identity attributes", null: true

      def saml_identity
        Models::ExternalIdentityAttributes.new(@object, as: :saml)
      end

      field :scim_identity, Objects::ExternalIdentityScimAttributes, description: "SCIM Identity attributes", null: true

      def scim_identity
        Models::ExternalIdentityAttributes.new(@object, as: :scim)
      end

      field :user, Objects::User, "User linked to this external identity. Will be NULL if this identity has not been claimed by an organization member.", null: true

      class AdminableMember < SimpleDelegator
        # Viewer is an administrator in this organization context and should be
        # able to see spammy members with external identities.
        def hide_from_user?(viewer)
          false
        end

        def platform_type_name
          # This object is a proxy to a user, with some methods added.
          "User"
        end
      end

      def user
        @object.async_user.then do |user|
          AdminableMember.new(user) if user.present?
        end
      end

      field :organization_invitation, Objects::OrganizationInvitation, "Organization invitation for this SCIM-provisioned external identity", method: :async_organization_invitation, null: true

      field :saml_user_data, String, "SAML user data for the external identity formatted as JSON", null: true, visibility: :internal

      def saml_user_data
        @object.async_identity_attribute_records.then do
          @object.saml_user_data.to_json
        end
      end

      field :scim_user_data, String, "SCIM user data for the external identity formatted as JSON", null: true, visibility: :internal

      def scim_user_data
        @object.async_identity_attribute_records.then do
          @object.scim_user_data.to_json
        end
      end

      field :disabled_at, Scalars::DateTime, "The date and time when the external identity was disabled, soft deleted.", null: true, visibility: :internal
      field :deleted_at, Scalars::DateTime, "The date and time when the external identity was deleted", null: true, visibility: :internal
      field :created_at, Scalars::DateTime, "The date and time that this external identity was created", null: false, visibility: :internal
      field :updated_at, Scalars::DateTime, "The date and time that this external identity was updated", null: false, visibility: :internal

      field :external_id, String, "The external ID for this identity populated from SCIM", null: true, visibility: :internal
      field :saml_external_id, String, "The external ID for this identity populated from SAML", null: true, visibility: :internal

      field :user_name, String, "The SCIM provisioned user name for this identity", null: true, visibility: :internal
      field :name_id, String, "The SAML NameID or other ID for this identity", null: true, visibility: :internal

      field :user_sessions, Connections.define(Objects::UserSession), description: "The user sessions for this external identity", null: false, connection: true, visibility: :internal

      def user_sessions
        @object.async_user_sessions.then do
          @object.user_sessions
        end
      end

      field :authorized_credentials, Connections.define(Objects::OrganizationCredentialAuthorization), description: "A list of AuthorizedCredentials for the user and SAML provider of this ExternalIdentity", null: false, connection: true

      def authorized_credentials
        Promise.all([
          @object.async_provider,
          @object.async_user,
        ]).then do
          @object.provider.async_target.then do
            @object.provider.target.credential_authorizations.
              where(actor: @object.user)
          end
        end
      end
    end
  end
end
