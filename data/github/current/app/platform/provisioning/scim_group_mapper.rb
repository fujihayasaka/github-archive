# typed: false
# frozen_string_literal: true

# Mapper responsible for taking GroupData provided via SCIM
# protocol and mapping that to an ExternalIdentity.
module Platform::Provisioning
  module SCIMGroupMapper
    PROVISIONING_NOT_ENABLED = "Provisioning was not enabled for SCIM.  Please enable SCIM provisioning in SAML configuration."

    # Public: Find a group that matches group data attributes, already provisioned from SAML
    #
    # Returns ExternalGroup or nil
    def self.find_group(target:, group_data:, filter_deleted: true)
      provider = target.external_identity_session_owner.external_provider

      unless group_data.external_id.nil?
        # Only lookup pre-existing SAML provisioned identities that match on the external id (OID)
        if filter_deleted
          group = ExternalGroup.by_provider(provider)
            .not_deleted
            .find_by_external_id(group_data.external_id)
        else
          group = ExternalGroup.by_provider(provider)
            .find_by_external_id(group_data.external_id)
        end
      end

      # For EMU use external id only for matching
      return group if target.is_a?(Business) && target.enterprise_managed_user_enabled?

      # For GHES with SCIM
      return group if target.saml_provider&.enterprise_server_scim_enabled?

      nil
    end

    # Builds a new group, will check if provisioning is enabled
    def self.build_group(target:)
      return nil unless scim_provisioning_enabled?(target: target)
      ExternalGroup.new(provider: target.external_identity_session_owner.external_provider)
    end

    def self.set_group_data(group:, group_data:)
      group.external_id = group_data.external_id
      group.display_name = group_data.display_name
    end

    # Public: Builds a new or finds an existing SAML provisioned identity from SCIM user data
    #
    # SCIM doesn't doesn't find existing SCIM provisioned identities based on SCIM user data
    # since it uses explicit create or update actions. An error will still
    # occur if attempting to create an identity with an existing 'userName'
    # attribute. ('userName' will mirror 'displayName' for Group Identities)
    #
    # target        - The Business which the identity will be under.
    # user          - Organization that this ExternalIdentity is for
    # user_data     - group data from the identity provider
    #
    # Returns an ExternalIdentity
    def self.find_or_build_identity(target:, user:, user_data:)
      provider = target.external_identity_session_owner.external_provider
      mapping = provider.identity_mapping

      # Only lookup pre-existing SAML provisioned identities.
      identity = ExternalIdentity.by_provider(provider)
        .get_by_identifier(user_data, mapping: mapping, identifier_attributes: mapping.saml_attribute, match_saml_identities: true)
        .first

      if identity
        # cleanup to make sure that the next time we won't treat this ExternalIdentity
        # as a SAML-provisioned one
        identity.saml_user_data = SamlGroupData.new
        identity.user = user
      else
        identity = ExternalIdentity.new(provider: provider, user: user)
      end

      identity
    end

    def self.set_user_data(identity:, user_data:)
      identity.scim_user_data = user_data

      # set user_name and external_id
      identity.user_name = user_data.user_name
      identity.external_id = user_data.external_id

      identity
    end

    # Public: Is SCIM provisioning enabled?
    # If GHES with SCIM or EMU business then default to
    # checking the scim_provisioning_state.
    # Otherwise return false.
    def self.scim_provisioning_enabled?(target:)
      if (target.is_a?(Business) && target.enterprise_managed_user_enabled?) ||
        GitHub.single_business_environment? && target.is_a?(Business) && target.saml_provider.present?
        target.oidc_enabled? || target.saml_provider.scim_provisioning_state_enabled?
      else
        false
      end
    end

    # Public: returns the error message when SCIM provisioning not enabled
    def self.provisioning_not_enabled
      PROVISIONING_NOT_ENABLED
    end
  end
end
