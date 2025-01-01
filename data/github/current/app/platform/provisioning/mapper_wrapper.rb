# typed: false
# frozen_string_literal: true

# A Wrapper for the ScimMapper module which adds support for migrating identities
# and for syncing the "groups" meta-data across the ExternalIdentity's UserData's.

module Platform
  module Provisioning
    class MapperWrapper

      # MapperWrapper - a wrapper for ScimMapper and SamlMapper modules with additional support
      # for migrating identities and syncing groups meta-data
      #
      # mapper                - the mapper module we're wrapping
      # can_migrate_identity  - can we migrate a previously created identity?
      # received_full_groups_info - did we receive the full list of groups this identity belongs to?
      #                             sync the groups meta-data in the "other" UserData, if we did.
      def initialize(mapper: ScimMapper, can_migrate_identity: false, received_full_groups_info: false)
        @mapper = mapper
        @can_migrate_identity = can_migrate_identity
        @received_full_groups_info = received_full_groups_info
      end

      # Builds a new or finds existing identity from the given UserData
      #
      # Can find a previously provisioned identity that matches the given user_data and migrate it
      # if `can_migrate_identity` parameter is true.
      #
      # ScimMapper doesn't use the user parameter here, but the returned ExternalIdentity can have
      # user_id set, if the previous identity we'll be migrating had it set.
      #
      # Returns: an ExternalIdentity (never nil, though may be un-saved)
      def find_or_build_identity(target:, user: nil, user_data:)
        identity = active_mapper.find_or_build_identity(target: target, user: user, user_data: user_data)

        return if identity.nil?

        # there was an existing identity from this provider, so return it
        return identity if identity.persisted? || !can_migrate_identity?

        identity_to_migrate = find_identity_for_migration(target: target, user_data: user_data)

        identity_to_migrate || identity
      end

      # Defers to the active_mapper for setting the appropriate user_data; can also optionally sync the groups
      # info in the "other" user_data if `received_full_groups_info` param is true and if the provider
      # is a Business::SamlProvider (i.e. not applicable to identities for Org SAML)
      #
      # identity -  ExternalIdentity to update
      # user_data - UserData object to assign to the identity
      #
      # Returns: the updated identity
      def set_user_data(identity:, user_data:)
        old_values = active_mapper.set_user_data(identity: identity, user_data: user_data)

        return old_values unless identity.provider.is_a?(Business::SamlProvider) && received_full_groups_info?

        sync_groups_data!(identity)
      end

      def can_migrate_identity?
        @can_migrate_identity
      end

      def received_full_groups_info?
        @received_full_groups_info
      end

      # The Mapper that the wrapper was initialized with. Corresponds to the operation
      # we're currently processing
      def active_mapper
        @mapper
      end

      # The "other" Mapper, corresponding to the UserData that's not being directly updated by the
      # current opetration. If we're processing a SCIM operation, ScimMapper is active, and
      # SamlMapper is secondary. For a SAML operation, SamlMapper is active, and ScimMapper is
      # secondary.
      def secondary_mapper
        return SamlMapper if active_mapper == ScimMapper
        ScimMapper
      end

      def scim_request?
        active_mapper == ScimMapper
      end

      def saml_request?
        active_mapper == SamlMapper
      end

      # Returns the UserData corresponding to the current operation.
      #
      # identity    -   ExternalIdentity whose user_data's we're looking at
      #
      # Returns: a SamlUserData or ScimUserData
      def active_user_data(identity)
        return identity.scim_user_data if scim_request?
        identity.saml_user_data
      end

      # Returns the "other" UserData based on the current operation. For a SCIM operation, the
      # active user data is saml_user_data, and scim_user_data is secondary. For a SCIM operation,
      # scim_user_data is active, and saml_user_data is secondary
      #
      # identity    -   ExternalIdentity whose user_data's we're looking at
      #
      # Returns: a SamlUserData or ScimUserData
      def secondary_user_data(identity)
        return identity.saml_user_data if scim_request?
        identity.scim_user_data
      end

      def to_s
        active_mapper.to_s
      end

      # Make sure that the "secondary" UserData on this identity doesn't include group membership
      # information that's not also present in the "active" UserData. "active" and "secondary"
      # depend on the operation we're processing and active_mapper. A ScimMapper is used to update
      # the scim_user_data, so it's "active", and saml_user_data is "secondary". SamlMapper is
      # used to update the saml_user_data, making it "active", and scim_user_data "secondary"
      #
      # Only applicable for Enterprise SAML, and if received_full_groups_info param is true. Will
      # return the unchanged `identity` otherwise.
      #
      # identity    -  ExternalIdentity to update
      #
      # Returns: the updated ExternalIdentity
      def sync_groups_data!(identity)
        return identity unless identity&.provider.is_a?(Business::SamlProvider) &&
                               received_full_groups_info?

        groups_wrapper = GroupsUserDataWrapper.new(secondary_user_data(identity))
        return identity if groups_wrapper.groups.empty?

        group_ids = identity.provider.group_ids(user_data: active_user_data(identity))
        updated_user_data = groups_wrapper.sync_group_attributes(valid_group_ids: group_ids)

        secondary_mapper.set_user_data(identity: identity, user_data: updated_user_data)

        identity
      end

      # Applies a SCIM operation to both UserData's on an ExternalIdentity object. Does not
      # mutate the currently active UserData object (waits for IdentityProvisioner to do so),
      # but does mutate the "other" UserData object on the ExternalIdentity, to make sure
      # it does not continue to grant access to a group that is being removed by the current
      # operation. Defers to SCIM::Operation.apply to do the actual work of updating the UserData.
      #
      # identity    - ExternalIdentity whose UserData is to be changed
      # operation   - A SCIM operation Hash.
      #
      # Returns: copy of the "active" UserData with the operation applied.
      def apply_operation_to_identity(identity, operation)
        unless operation["op"] == "add"
          # First apply operation and update the secondary user_data.
          # N/A for "add" operations - we just need to make sure that the ExternalIdentity fully
          # loses access to the group it's being removed from, so need to make sure neither
          # UserData grants access. For adding access, we just need one of the UserData's to
          # reference it, so no reason to update the "other" one
          patched_user_data = SCIM::Operation.apply(secondary_user_data(identity), operation)
          secondary_mapper.set_user_data(identity: identity, user_data: patched_user_data)
        end

        # Then apply the operation and return an updated copy of the currently active user_data
        SCIM::Operation.apply(active_user_data(identity), operation)
      end

      # Finds a previously provisioned identity for the given user_data. If we find a SCIM identity
      # provisioned by the current SamlProvider (likely means the org or enterprise has updated
      # its SAML settings), return it. ScimMapper.find_or_build_identity will automatically find
      # SAML-provisioned identities. Not used for SamlMapper.
      #
      # If target is an Enterprise, and we find an identity provisioned by
      # a provider of one of its organizations, make a copy of it. We don't want to change the
      # org-provisioned identity, since it might be used again (if the org's SAML is ever
      # re-enabled: org leaves the Enterprise, or the Enterprise disables SAML)
      #
      # Returns: an ExternalIdentity (can be nil)
      def find_identity_for_migration(target:, user_data:)
        return nil unless target.saml_sso_enabled?
        return nil unless can_migrate_identity?
        return nil unless active_mapper == ScimMapper
        provider = target.saml_provider

        # Look up an ExternalIdentity for this provider that was provisioned before the provider
        # was last updated. If the SAML configuration for an org/enterprise is changed, its
        # SamlProvider object (and all of its associated ExternalIdentity's) will persist, but
        # will be updated. So, look up identities whose `created_at` timestamp is before the
        # provider's `updated_at` timestamp. Happens when the IdP thinks it's starting from scratch
        # and needs to re-provision all the identities.
        external_identity = provider.external_identities
          .get_by_identifier(user_data, mapping: provider.identity_mapping,
                             identifier_attributes: provider.identity_mapping.scim_attribute)
          .where("`external_identities`.created_at < ?", provider.updated_at)
          .first

        return external_identity unless external_identity.nil?
        return nil unless provider.is_a?(Business::SamlProvider)

        org_saml_provider_ids = Organization::SamlProvider.
          where(organization_id: target.organization_ids).pluck(:id)
        return nil if org_saml_provider_ids.empty?

        # Look up ExternalIdentity's provisioned by SamlProvider's of the Enterprise's member orgs.
        # If we find one, that likely means that it's associated with a user who's already a member
        # of the org, so we can just use it and leave the member in place, instead of removing and
        # re-inviting them (if Enterprise Membership Provisioning is enabled and the IdP is
        # configured to talk to the /Groups SCIM endpoint)
        org_identity_to_migrate = ExternalIdentity.
          where(provider_id: org_saml_provider_ids, provider_type: Organization::SamlProvider).
          get_by_identifier(user_data, mapping: provider.identity_mapping).
          first

        return nil if org_identity_to_migrate.nil?

        # Don't use the identity directly - make a copy and leave the original in place, in case it
        # needs to be used again (if org SAML gets re-enabled)
        external_identity = ExternalIdentity.new(
          user_id: org_identity_to_migrate.user_id,
          provider_id: provider.id,
          provider_type: Business::SamlProvider
        )
        # Grab any SAML data from the old identity; let the current operation set the new SCIM data
        if org_identity_to_migrate.saml_user_data.any?
          external_identity.saml_user_data = org_identity_to_migrate.saml_user_data.dup
        end

        external_identity
      end

      # Returns an error message when provisioning for the active mapper is not enabled
      def provisioning_not_enabled
        active_mapper.provisioning_not_enabled
      end

      def validate_identity_relink(target:, user:, user_data:)
        active_mapper.validate_identity_relink(target: target, user: user, user_data: user_data)
      end
    end
  end
end
