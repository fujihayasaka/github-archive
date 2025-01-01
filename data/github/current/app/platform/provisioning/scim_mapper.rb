# typed: false
# frozen_string_literal: true

# Mapper responsible for taking UserData provided via SCIM
# protocol and mapping that to an ExternalIdentity.
#
# SCIM Mapper is used in multiple environments and it expects to map to an external identity record
# that already exists in the database. The key is how the lookup is done and which value we want to
# look at to match the identity. SCIM mapper matches against the external_id column of the external identity
# first and falls back to NameID (only for Enterprise and Organization SCIM).
# If a match is not found in any of the cases above then we fall back to the external identity attributes
# table and look for the externalId, userName, and NameID attributes respectively
#
# Query pattern for lookups:
#           Organization   |   Enterprise   |      Azure EMU/GHES     |   Okta EMU/GHES
#  SAML      ExI -> NiD    |   Exi -> NiD   |          ExI            |         UsN
#  SCIM      ExI -> NiD    |   Exi -> NiD   |          ExI            |         ExI
#
# Legend: ExI - External Id
#         NiD - NameID from SAML
#         UsN - Username from SCIM
#
# example: ExI -> NiD means that during lookups, we first look for a match on the
# external_identity.external_id and if one is not found we then look for a match on the
# external_identity.name_id
module Platform
  module Provisioning
    module ScimMapper
      PROVISIONING_NOT_ENABLED = "Provisioning was not enabled for SCIM.  Please enable SCIM provisioning in SAML configuration."

      # Public: Find an identity that matches user data attributes, already provisioned from SAML
      #
      # SCIM identities are matched by a GUID, so this is the match when SCIM identity
      # was not created
      #
      # Returns ExternalIdentity or nil
      def self.find_identity(target:, user_data:)
        if target.is_a?(Business)
          provider = target.external_identity_session_owner.external_provider
        else
          provider = target.external_identity_session_owner.saml_provider
        end
        mapping = provider.identity_mapping

        unless user_data.external_id.nil?
          # Only lookup pre-existing SAML provisioned identities that match on the external id (OID)
          identity = if target.enterprise_managed_user_enabled?
            # For EMUs user external_id column, used in the get_by_external_id_scim method
            ExternalIdentity.by_provider(provider)
              .not_deleted
              .get_by_external_id_scim(user_data, mapping: mapping, external_id_attributes: mapping.saml_external_id_attribute)
              .first
          else
            ExternalIdentity.by_provider(provider)
              .not_deleted
              .get_by_external_id(user_data, mapping: mapping, external_id_attributes: mapping.saml_external_id_attribute)
              .first
          end
        end

        # For EMU use external id only for matching
        return identity if target.is_a?(Business) && target.enterprise_managed_user_enabled?

        # For GHES with SCIM
        return identity if target.saml_provider&.enterprise_server_scim_enabled?

        # saml only has to be set to true, since saml_attributes contain username and since database
        # is running in case insensitive mode, it will match on the scim userName attribute case insensitively
        identity ||= ExternalIdentity.by_provider(provider)
          .not_deleted
          .get_by_identifier(user_data, mapping: mapping, identifier_attributes: mapping.saml_attribute, match_saml_identities: true)
          .first
      end

      # Builds a new identity, will check if provisioning is enabled
      def self.build_identity(target:)
        return nil unless provisioning_enabled?(target: target)
        if target.is_a?(Business)
          ExternalIdentity.new(provider: target.external_identity_session_owner.external_provider)
        else
          ExternalIdentity.new(provider: target.external_identity_session_owner.saml_provider)
        end
      end

      # Builds a new or finds existing SAML provisioned identity from SCIM user data
      #
      # SCIM doesn't find existing SCIM provisioned identities based on SCIM user data
      # since it uses explicit create or update actions. An error will still
      # occur if attempting to create an identity with an existing 'userName'
      # attribute.
      #
      # Additionally, SCIM doesn't care about the user since it only deals
      # with creating the identity and never linking the identity to a user.
      def self.find_or_build_identity(target:, user: nil, user_data:)
        identity = find_identity(target: target, user_data: user_data)
        identity ||= build_identity(target: target)
      end

      def self.set_user_data(identity:, user_data:)
        old_values = {
          external_id: identity.external_id,
          user_name: identity.user_name,
          user_id: identity.user_id,
          scim_user_data: identity.scim_user_data,
        }

        identity.scim_user_data = user_data

        return unless user_data.is_a?(AttributeMappedUserData)

        # update the external id if it's not already populated
        identity.external_id = user_data.external_id if user_data.external_id.present?

        # update the user_name
        identity.user_name = user_data.user_name if user_data.user_name.present?
        identity.user_name ||= user_data.primary_email if user_data.primary_email.present?

        old_values
      end

      # Public: Can the user be unsuspended by this call
      def self.can_unsuspend_user?(target)
        true
      end

      # Public: Returns true when target is EMU or GHES with SCIM enabled
      def self.scim_provisioning_enabled?(target)
        target.is_a?(Business) && target.enterprise_managed_user_enabled? ||
        GitHub.single_business_environment? && target.is_a?(Business) && target.saml_provider&.scim_provisioning_state_enabled?
      end

      # Public: Expect user_data.present? to be true and user_data.external_id.present? to be set
      def self.provisioning_user_data_valid?(user_data)
        user_data.external_id.present?
      end

      # Public: Returns a type of a mapper
      def self.type
        :scim
      end

      # Public: Is SCIM provisioning enabled?
      # If EMU business then default to
      # checking the scim_provisioning_state.
      # Otherwise return true.
      def self.provisioning_enabled?(target:)
        if target.is_a?(Business) && target.enterprise_managed_user_enabled?
          target.oidc_enabled? || target.saml_provider.scim_provisioning_state_enabled?
        elsif GitHub.single_business_environment? && target.is_a?(Business)
          target.saml_provider&.scim_provisioning_state_enabled?
        else
          true
        end
      end

      # Public: returns the error message when SCIM provisioning not enabled
      def self.provisioning_not_enabled
        PROVISIONING_NOT_ENABLED
      end

      # Public: check whether or not the user's identity will be relinked
      # during provisioning
      #
      # target  - The Business the identity is under.
      # user      - The User the identity is linked to.
      # user_data - The Platform::Provisioning::UserData with all of the
      #             IdP provided data about the user.
      #
      # Returns an error if we are relinking - always nil for SCIM
      def self.validate_identity_relink(target:, user:, user_data:)
        nil
      end
    end
  end
end
