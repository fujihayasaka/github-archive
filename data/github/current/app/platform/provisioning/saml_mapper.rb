# typed: false
# frozen_string_literal: true

# Mapper responsible for taking UserData provided by the identity provider
# via SAML protocol and mapping that to an ExternalIdentity.
#
# SAML Mapper is used in multiple environments and it expects to map to an external identity record
# that already exists in the database. The key is how the lookup is done and which value we want to
# look at to match the identity. SAML mapper matches against the name_id column of the external identity.
# If a match is not found on the external identity then we fall back to the external identity attributes
# table and look for the NameID attribute.
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
module Platform::Provisioning
  module SamlMapper
    ENTERPRISE_PROVISIONING_NOT_ENABLED = "Provisioning of users is managed by your identity provider via SCIM. This user has not been provisioned or has been deprovisioned in your enterprise. Please contact your administrator to address this issue."
    ENTERPRISE_PROVISIONING_NOT_ENABLED_WITH_ATTRIBUTES = "Provisioning of users is managed by your identity provider via SCIM. Using your SAML %{saml_attribute_name} attribute (%{saml_attribute_value}), we were unable to locate an active external identity with a matching SCIM %{scim_attribute_name} value. Please contact your administrator to address this issue."
    EMU_PROVISIONING_NOT_ENABLED = "Enterprise Managed Users must be provisioned via SCIM. Please reach out to your account manager for more information."
    DEFAULT_SAML_MAPPER_IDENTIFIER = {
      name_id: [:okta, :unknown],
      external_id: [:azure_ad]
    }

    # Public: Find an identity that matches attributes of a user data, already provisioned via SAML or SCIM
    #
    # Returns ExternalIdentity or nil
    # Since this method will use a read replica, there will be a slight delay. You should avoid calling this method immediately after creating an identity
    def self.find_identity(target:, user_data:)
      ActiveRecord::Base.connected_to(role: :reading) do
        provider = target.external_identity_session_owner.saml_provider
        mapping = provider.identity_mapping

        # SAML mapper should only match on identities that were not deleted and not disabled (soft deleted)
        external_identity_scope = ExternalIdentity.by_provider(provider)
          .not_disabled_and_deleted

        if scim_provisioning_enabled?(target)
          if DEFAULT_SAML_MAPPER_IDENTIFIER[:name_id].include?(provider.find_provider_type)
            external_identity_scope.get_by_identifier(user_data, mapping: mapping).first
          else
            external_identity_scope.get_by_external_id(user_data, mapping: mapping).first
          end
        else
          unless user_data.external_id.nil?
            # Only lookup pre-existing SAML provisioned identities that match on the external id (OID)
            identity = external_identity_scope.get_by_external_id(user_data, mapping: mapping).first
          end

          identity ||= external_identity_scope.get_by_identifier(user_data, mapping: mapping).first
        end
      end
    end

    # Builds a new identity, will check if provisioning is enabled
    def self.build_identity(target:)
      return nil unless provisioning_enabled?(target: target)
      ExternalIdentity.new(provider: target.external_identity_session_owner.saml_provider)
    end

    # Public: Finds or builds an external identity for a user and an Organization or Business
    # as specified by the passed provisioning user data.
    #
    # target        - The Organization or Business which the identity will be under.
    # user          - (Optional) The User to whom the identity will be linked.
    # user_data     - The Platform::Provisioning::UserData which specifies any
    #                 information about the user provided by the IdP.
    #
    # Returns an ExternalIdentity, or nil if no existing identity found and saml provisioning is disabled
    def self.find_or_build_identity(target:, user: nil, user_data:)
      if user
        identity_for_user(target: target, user: user, user_data: user_data)
      else
        identity_for_anon(target: target, user_data: user_data)
      end
    end

    # Internal: Finds or builds an external identity for an Organization or Business
    # as specified by the passed provisioning user data.
    #
    # If a provisioned identity already exists for the specified name_id, it is returned
    # even if it is already provisioned and linked to a user. We only care if we have
    # a record of the identity. This is useful for cases where an anonymous user goes
    # through the single sign on flow since they are able to sign in after going through
    # the flow.
    #
    # If no existing identity exists, a new one will be built.
    #
    # target        - The Organization or Business which the identity will be under.
    # user_data     - The Platform::Provisioning::UserData which specifies any
    #                 information about the user provided by the IdP.
    #
    # Returns an ExternalIdentity, or nil if no existing identity found and saml provisioning is disabled
    def self.identity_for_anon(target:, user_data:)
      identity = find_identity(target: target, user_data: user_data)
      identity ||= build_identity(target: target)
    end

    # Internal: Finds or builds an external identity for a user and an Organization or Business
    # as specified by the passed provisioning user data.
    #
    # If an identity already exists for this user, it is returned even if the
    # name_id doesn't match the one provided by user_data. We'll update the identity
    # to use the latest name_id provided by the identity provider.
    #
    # If an identity already exists for the specified name_id which is not yet
    # linked to a user, link it to this user and return it.
    #
    # Otherwise build a brand new identity for this user using the provided
    # UserData.
    #
    # target        - The Organization or Business which the identity will be under.
    # user          - The User whom the identity will be linked.
    # user_data     - The Platform::Provisioning::UserData which specifies any
    #                 information about the user provided by the IdP.
    #
    # Returns an ExternalIdentity, or nil if no existing identity found and saml provisioning is disabled
    def self.identity_for_user(target:, user:, user_data:)
      provider = target.external_identity_session_owner.saml_provider

      # Look for an identity provisioned by SCIM which matches the user's emails first.
      identity = link_unlinked_scim_identity!(provider: provider, user: user, user_data: user_data)

      # Existing linked identity
      ActiveRecord::Base.connected_to(role: :reading) do
        identity ||= ExternalIdentity.by_provider(provider).linked_to(user).first
      end

      if user_data.is_a?(AttributeMappedUserData) && user_data.external_id.present?
        mapping = provider.identity_mapping

        # Will match to an unlinked external identity record using
        # external id, for which an invitation has been sent
        # At which point the identity record is not linked to a user
        ActiveRecord::Base.connected_to(role: :reading) do
          identity ||= ExternalIdentity.by_provider(provider)
            .not_deleted
            .unlinked
            .get_by_external_id(user_data, mapping: mapping)
            .first
        end
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        identity ||= ExternalIdentity.by_provider(provider)
          .unlinked
          .get_by_identifier(user_data, mapping: provider.identity_mapping)
          .first
      end

      identity ||= ExternalIdentity.new(provider: provider, user: user) if provisioning_enabled?(target: target)

      identity.user = user unless identity.nil?
      identity
    end

    def self.link_unlinked_scim_identity!(provider:, user:, user_data:)
      identity = ActiveRecord::Base.connected_to(role: :reading) do
        external_identity_ids = ExternalIdentityAttribute.select(:external_identity_id).distinct
          .where(value: Array.wrap(UserEmail.safe_bulk_normalize(users: user, verified: true)), name: :emails, scheme: :scim)
          .pluck(:external_identity_id)

        unless external_identity_ids.empty?
          ExternalIdentity.by_provider(provider).unlinked.where(id: external_identity_ids).first
        end
      end

      if identity
        # If the user already had an identity in the org via manual SSO,
        # linking this identity will fail since it's a duplicate. Remove any
        # existing identities first before linking this one.
        ExternalIdentity.unlink(provider: provider, user: user)

        # Also remove any unlinked identities which have the same identifier
        # and make sure we do not remove the currently selected candidate identity
        ExternalIdentity.by_provider(provider).unlinked
          .get_by_identifier(user_data, mapping: provider.identity_mapping)
          .where.not(id: identity.id)
          .destroy_all
      end

      identity
    end

    def self.set_user_data(identity:, user_data:)
      old_values = {
        external_id: identity.external_id,
        name_id: identity.name_id,
        user_id: identity.user_id_was,
        saml_user_data: identity.saml_user_data,
      }

      identity.saml_user_data = user_data

      return unless user_data.is_a?(AttributeMappedUserData)

      # update external_id
      identity.saml_external_id = user_data.external_id if user_data.external_id.present?

      # update name_id
      # user_name is a method that surfaces NameID attribute value for SAML user_data
      identity.name_id = user_data.name_id if user_data.name_id.present?
      identity.name_id ||= user_data.user_name if user_data.user_name.present?

      old_values
    end

    # Public: Can the user be unsuspended by this call
    # This can be done as configuration change in the future
    def self.can_unsuspend_user?(target)
      return false if scim_provisioning_enabled?(target)
      true
    end

    # Public: Returns true when target is EMU or GHES with SCIM enabled
    def self.scim_provisioning_enabled?(target)
      target.is_a?(Business) && target.enterprise_managed_user_enabled? ||
      GitHub.single_business_environment? && target.is_a?(Business) && target.saml_provider&.scim_provisioning_state_enabled?
    end

    # Public: Expect user_data.present? to be true during provisioning
    def self.provisioning_user_data_valid?(user_data)
      true
    end

    # Public: Returns a type of a mapper
    def self.type
      :saml
    end

    # Public: Is SAML provisioning enabled?
    # Returns true if not an EMU business.
    # If an EMU business then return false as SAML provisioning is not enabled for EMUs.
    # otherwise check if saml provider is set with scim_provisioning_state_enabled?
    def self.provisioning_enabled?(target:)
      # this whole check can be removed if we want to enable SAML JIT provisioning capability for EMU in the future
      return false if target.is_a?(Business) && target.enterprise_managed_user_enabled?

      return !target.saml_provider&.scim_provisioning_state_enabled? if GitHub.single_business_environment? && target.is_a?(Business)

      true
    end

    # Public: returns the appropriate EMU error message when SAML provisioning not enabled.
    def self.provisioning_not_enabled(target: nil, user_data: nil)
      if GitHub.single_business_environment?
        provider = target&.saml_provider
        return ENTERPRISE_PROVISIONING_NOT_ENABLED unless provider.present? && user_data.present?

        mapping = provider.identity_mapping
        attributes = if DEFAULT_SAML_MAPPER_IDENTIFIER[:external_id].include?(provider.find_provider_type)
          # The provider is :azure_ad. Find the attribute used in the lookup in the external identity method :get_by_external_id
          saml_attribute_name = find_saml_attribute_name(mapping.saml_external_id_attribute, user_data, "http://schemas.microsoft.com/identity/claims/objectidentifier")

          {
            saml_attribute_name: saml_attribute_name,
            saml_attribute_value: user_data.external_id,
            scim_attribute_name: "external ID"
          }
        else
          # The provider is :okta or :unknown. Find the attribute used in the lookup in the external identity method :get_by_identifier
          # (see attributes used in value_from_user_data in Platform::Provisioning::IdentityMapping)
          saml_attribute_name = find_saml_attribute_name(mapping.identifier_attributes, user_data, GitHub.saml_username_attr || "NameID")

          {
            saml_attribute_name: saml_attribute_name,
            saml_attribute_value: mapping.value_from_user_data(user_data),
            scim_attribute_name: "user name"
          }
        end

        return ENTERPRISE_PROVISIONING_NOT_ENABLED_WITH_ATTRIBUTES % attributes
      end

      EMU_PROVISIONING_NOT_ENABLED
    end

    # Public: check whether or not the user's identity will be relinked
    # during provisioning
    #
    # target  - The Business the identity is under.
    # user      - The User the identity is linked to.
    # user_data - The Platform::Provisioning::UserData with all of the
    #             IdP provided data about the user.
    #
    # Returns a relink error if the user's identity will be relinked, nil otherwise
    def self.validate_identity_relink(target:, user:, user_data:)
      provider = target.saml_provider
      return nil unless current_identity = user.external_identities.by_provider(provider).first

      mapping = provider.identity_mapping
      identifier = mapping.value_from_user_data(user_data).presence

      current_identity_identifier = current_identity.name_id || current_identity.user_name

      if (current_identity.saml_external_id.present? || current_identity.external_id.present?) && user_data.external_id.present?
        if mismatched_external_id?(current_identity, user_data)
          Platform::Provisioning::Error.identity_relink_error(current_identity_identifier: current_identity_identifier, new_identity_identifier: identifier)
        end
      elsif current_identity_identifier != identifier
        Platform::Provisioning::Error.identity_relink_error(current_identity_identifier: current_identity_identifier, new_identity_identifier: identifier)
      end
    end

    private_class_method def self.mismatched_external_id?(current_identity, user_data)
      if current_identity.saml_external_id.present?
        current_identity.saml_external_id != user_data.external_id
      else
        current_identity.external_id != user_data.external_id
      end
    end

    private_class_method def self.find_saml_attribute_name(attributes, user_data, default_attribute)
      found_value = nil
      saml_attribute_name = default_attribute

      attributes.each do |attribute|
        found_value = user_data.fetch(attribute, {})["value"]
        if found_value
          saml_attribute_name = attribute
          break
        end
      end

      saml_attribute_name
    end
  end
end
