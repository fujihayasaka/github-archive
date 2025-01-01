# typed: false
# frozen_string_literal: true

class Platform::Provisioning::BaseIdentityProvisioner < Platform::Provisioning::ProvisionerStatus
  # Public: Finds all external identity records for a target and a mapper type.
  #
  # target          - The target the identity is under. Business or organization.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns Result record
  def self.find_all(
    target:,
    mapper:
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present?

    identities = new(target: target, mapper: mapper, user_data: nil).
      find_all_identities

    success_identity_status(identities)
  end

  # Public: Find the external identity record. If the Identity GUID was provided it is used to
  #  exactly match it, otherwise the data from the user_data is used through a mapper.
  #
  # target          - The target the identity is under. Business or organization.
  # identity_guid   - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # user_data       - (optional) The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about a user.
  # mapper          - (optional) The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns Result record
  def self.find(
    target:,
    identity_guid: nil,
    user_data: nil,
    mapper: nil
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present?
    return internal_error_status unless mapper.present? || identity_guid.present?
    return internal_error_status unless user_data.present? || identity_guid.present?

    identity = new(target: target, mapper: mapper, user_data: user_data).
      find_identity(
        identity_guid: identity_guid,
      )

    return identity_not_found_error_status if identity.nil?
    success_identity_status(identity)
  end

  # Public: Provisions an identity under the target.
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # user_id         - (optional) The ID of the User the identity is linked to.
  # inviter_id      - (Optional) The ID of the user sending the invitation. Useful when
  #                   updating a pending invitation
  # inviter_type    - The type of the actor sending the invitation (defaults to User).
  #
  # Returns Result record
  def self.provision(
    target:,
    user_data:,
    mapper:,
    user_id: nil,
    inviter_id: nil,
    inviter_type: User
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && user_data.present?
    return bad_request_status unless mapper.provisioning_user_data_valid?(user_data)

    new(target: target, mapper: mapper, user_data: user_data).
      provision_identity(
        user_id: user_id,
        inviter_id: inviter_id,
        inviter_type: inviter_type,
      )
  end

  # Public: Updates an identity under the target can take a block
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # user_id         - (optional) The ID of the User the identity is linked to.
  # identity_guid   - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # identity        - (optional) an external identity record
  # actor_id        - Id of the actor making the deprovision request
  # sso_invitation_token - (optional) The ID of the Organization::Invitation being accepted
  #                   on behalf of the user.
  #
  # Returns Result record
  def self.update(
    target:,
    user_data:,
    mapper:,
    user_id: nil,
    identity_guid: nil,
    identity: nil,
    actor_id: nil,
    sso_invitation_token: nil
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && user_data.present?
    return bad_request_status unless mapper.provisioning_user_data_valid?(user_data)

    new(target: target, mapper: mapper, user_data: user_data).
      update_identity(
        user_id: user_id,
        identity_guid: identity_guid,
        identity: identity,
        actor_id: actor_id,
        sso_invitation_token: sso_invitation_token,
      )
  end

  # Public: Updates or provisions an identity under the target, used in SAML flow only to facilitate
  #         just-in-time provisioning.
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML).
  # user_id         - (optional) The ID of the User the identity is linked to.
  # sso_invitation_token - (optional) The ID of the Organization::Invitation being accepted
  #                   on behalf of the user.
  # inviter_id      - (Optional) The ID of the user sending the invitation. Useful when
  #                   updating a pending invitation
  # inviter_type    - The type of the actor sending the invitation (defaults to User).
  #
  # Returns Result record
  def self.provision_or_update(
    target:,
    user_data:,
    mapper:,
    user_id: nil,
    sso_invitation_token: nil,
    inviter_id: nil,
    inviter_type: User
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && user_data.present?
    return bad_request_status unless mapper.provisioning_user_data_valid?(user_data)

    new(target: target, mapper: mapper, user_data: user_data).
      provision_or_update_identity(
        user_id: user_id,
        sso_invitation_token: sso_invitation_token,
        inviter_id: inviter_id,
        inviter_type: inviter_type,
      )
  end

  # Public: De-provisions an identity and removes user from the enterprise.
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  # actor_id        - Id of the actor making the deprovision request
  # identity_guid   - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # identity        - (optional) an external identity record
  #
  # Returns Result record
  def self.deprovision(
    target:,
    user_data:,
    mapper:,
    actor_id:,
    identity_guid: nil,
    identity: nil
  )
    return internal_error_status \
      unless target.present? && target.external_provider.present? && mapper.present? && user_data.present? && actor_id.present?

    new(target: target, mapper: mapper, user_data: user_data).
      deprovision_identity(
        actor_id: actor_id,
        identity_guid: identity_guid,
        identity: identity,
      )
  end

  # Public: Attempts to find an external identity and the user account
  # using the details returned by the identity provider. This method is
  # for SCIM managed enterprises.
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  #
  # Returns a Platform::Provisioning:Result
  def self.find_user_in_scim_managed_enterprise(target:, user_data:, mapper:)
    result = self.find \
      target: target,
      user_data: user_data,
      mapper: mapper

    # If the user isn't found in GitHub but is in the IDP, we should return the SCIM managed enterprise specific error message.
    return Platform::Provisioning::ProvisionerStatus.provisioning_not_enabled(mapper.provisioning_not_enabled(target: target, user_data: user_data)) if result.identity_not_found_error?

    # If the user is suspended, don't let them log in. Return the error message about the user being suspended.
    return Platform::Provisioning::ProvisionerStatus.user_suspended_status(result.external_identity) if result.user&.suspended?

    result
  end

  # define attribute readers for the instance
  attr_reader :target, :user_data, :mapper, :role_reconciler
  attr_accessor :role_reconciler_operation

  # Initialize an instance of a class
  #
  # target          - The target the identity is under. Currently Business and Organization
  #                   objects can be targeted.
  # user_data       - The Platform::Provisioning::AttributeMappedUserData with all of the
  #                   IdP provided data about the user.
  #                   specific for the provisioning scheme (e.g. SAML vs SCIM).
  # mapper          - The provisioning mapper responsible for mapping the
  #                   provided user_data to an external identity. This is
  def initialize(target:, user_data:, mapper:)
    @target = target
    @user_data = user_data
    @mapper = mapper
    @role_reconciler = Platform::Provisioning::RoleReconciler.new(target: target, mapper: mapper, user_data: user_data)
  end

  # Note the methods below are override points for subclasses
  # they will not change the interface, but can provide a different
  # way of processing data for each provisioner

  # Internal: This method returns all identities for a given mapper type
  #
  # Returns an Array of ExternalIdentities
  def find_all_identities
    # Okta will never delete an identity, so the query needs to be modified
    # to only return not disabled identities
    if Business.scim_provider_type == :okta
      target.external_provider.external_identities.not_disabled.
        provisioned_by(mapper.type)
    else
      target.external_provider.external_identities.not_deleted.
        provisioned_by(mapper.type)
    end
  end

  # Internal: This method performs a find of a single identity, it can search by an
  #   identity guid or mapper and user data
  #
  # Returns ExternalIdentities instance of nil
  def find_identity(identity_guid: nil)
    if identity_guid.present?
      target.external_provider
        .external_identities
        .not_deleted
        .find_by_guid(identity_guid)
    else
      mapper.find_identity(target: target, user_data: user_data) unless user_data.nil?
    end
  end

  # Private: Provisions a new identity and yields it to a block if given
  #
  # user_id         - The ID of the User the identity is linked to.
  # inviter_id      - The ID of the user sending the invitation. Useful when
  #                   updating a pending invitation
  # inviter_type    - The type of the actor sending the invitation (defaults to User).
  #
  # Returns Result record
  def provision_identity(
    user_id:,
    inviter_id:,
    inviter_type:,
    skip_find_identity: false
  )
    login = user_data.user_name
    return self.class.missing_login_status if login.blank?

    unless skip_find_identity
      # check if the identity has not been provisioned already
      identity = find_identity
      return self.class.duplicate_identity_found unless identity.nil?
    end

    # create new identity record and check for provisioning
    identity = mapper.build_identity(target: target)
    return self.class.provisioning_not_enabled(mapper.provisioning_not_enabled) if identity.nil?

    # identity can be provisioned in an unlinked state
    # only return an error when user_id was given and user was not found
    # user_id is here to support
    return self.class.internal_error_status unless user_id.nil? || user = User.find_by_id(user_id)

    result = save_provisioned_identity(identity: identity, user: user, inviter_id: inviter_id, inviter_type: inviter_type)

    # if the result is a failure don't proceed
    return result if target.feature_enabled?(:return_provision_identity_on_error) && !result.success?

    # if the user is provisioned with active flag set to false run an update
    # to set the user as suspended and disabled the identity
    if !user_data.active?
      result = update_identity(
        user_id: user_id,
        identity_guid: identity.guid,
        identity: identity,
        actor_id: inviter_id,
        sso_invitation_token: nil,
        reconcile_user: false,
      )
    else
      if result && result.success?
        start_user_contribution_cache_refresh_job(identity.user)
      end
    end

    result
  end

  # Private: Updates an identity and yields it to a block if given
  #
  # user_id         - (optional) The ID of the User the identity is linked to.
  # identity_guid   - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # identity        - (optional) an external identity record
  # actor_id        - Id of the actor making the deprovision request
  # sso_invitation_token - (optional) The ID of the Organization::Invitation being accepted
  #                   on behalf of the user.
  #
  # Returns Result record
  def update_identity(
    user_id:,
    identity_guid:,
    identity:,
    actor_id:,
    sso_invitation_token:,
    reconcile_user: true
  )
    # check for a valid username
    username = user_data.user_name
    return self.class.missing_login_status if username.blank?

    # if external identity was not provide
    if identity.nil?
      identity = find_identity(identity_guid: identity_guid)
      return self.class.identity_not_found_error_status if identity.nil?
    end

    user_id ||= identity.user_id

    # check if a user has been suspended and cannot be unsuspended by this call
    return self.class.user_suspended_status(identity) if identity.user.suspended? && !mapper.can_unsuspend_user?(target)

    # suspending a user in a separate transaction before the
    # reconciliation of a user is done (just in case it fails)
    unless user_data.active? || identity.user&.suspended?
      return self.class.internal_error_status unless actor = User.find_by_id(actor_id)
      return self.class.cannot_deprovision_self_error_status if identity.user_id == actor_id

      result = suspend_user(identity: identity, actor: actor)
      return result unless result.success?
    end

    # Set the user which must exist either on an identity or by finding it through a user id
    return self.class.internal_error_status unless user = identity.user || User.find_by_id(user_id)

    self.role_reconciler_operation = :update

    result = save_updated_identity(identity: identity, user: user, actor_id: actor_id,
      sso_invitation_token: sso_invitation_token, reconcile_user: reconcile_user)

    if result && result.success?
      start_user_contribution_cache_refresh_job(user)
    end

    result
  end

  # Public: Updates or provisions an identity under the target, used in SAML flow only to facilitate
  #         just-in-time provisioning.
  #
  # user_id         - (optional) The ID of the User the identity is linked to.
  # sso_invitation_token - (optional) The ID of the Organization::Invitation being accepted
  #                   on behalf of the user.
  # inviter_id      - (Optional) The ID of the user sending the invitation. Useful when
  #                   updating a pending invitation
  # inviter_type    - The type of the actor sending the invitation (defaults to User).
  #
  # Returns Result record
  def provision_or_update_identity(
    user_id:,
    sso_invitation_token:,
    inviter_id:,
    inviter_type:
  )
    identity = find_identity

    # Provision identity if it was not found
    if identity.nil?
      provision_identity(
        user_id: user_id,
        inviter_id: inviter_id,
        inviter_type: inviter_type,
        skip_find_identity: true,
      )
    else
      update_identity(
        user_id: user_id,
        identity_guid: nil,
        identity: identity,
        actor_id: inviter_id,
        sso_invitation_token: sso_invitation_token,
      )
    end
  end

  # Public: De-provisions an identity and removes user from the enterprise.
  #
  # actor_id        - Id of the actor making the deprovision request
  # identity_guid   - (optional) The GUID of the external identity to
  #                   provision. If not specified, the mapper will be used
  #                   to find or build one.
  # identity        - (optional) an external identity record
  #
  # Returns Result record
  def deprovision_identity(
    actor_id:,
    identity_guid:,
    identity:
  )
    # if external identity was not provide
    if identity.nil?
      identity = find_identity(identity_guid: identity_guid)
      return self.class.identity_not_found_error_status if identity.nil?
    end

    # Actor must be a valid user and it cannot be a user itself
    return self.class.internal_error_status unless actor = User.find_by_id(actor_id)
    return self.class.cannot_deprovision_self_error_status if identity.user_id == actor_id

    user = identity.user

    if user
      # suspend  user on a separate transaction
      result = suspend_user(identity: identity, actor: actor)
      return result unless result.success?
    end

    result = save_deprovisioned_identity(identity: identity, user: user, actor_id: actor_id)

    # check if the user was suspended
    if user
      return self.class.internal_error_status unless user.reload.suspended?
    end

    self.role_reconciler_operation = :deprovision

    result
  end

  # User provisioning section

  # Internal: This method or portions of the method can be overwritten depending
  #  on the needs of the provisioner
  #
  def find_or_provision_user(
    identity:
  )
    # This will normalize the username and search for it.
    user, message = find_legacy_user

    return self.class.login_conflict_status(message: message) if message

    # return invalid_identity_error if the user already exists and is not linked in the Enterprise,
    # or if message indicates this is an org
    return self.class.login_conflict_status if user && !valid_user_to_link_identity?(user: user, identity: identity)

    self.role_reconciler_operation = :provision
    # create a user unless the user already exists and is linked to the Enterprise
    # this is validated above
    return provision_user unless user

    self.role_reconciler_operation = :update
    self.class.success_user_status(user)
  end

  # Internal: Find user and check for errors, username will be standardized
  #    so not search by email is necessary
  #
  # Returns a tuple user or error message
  def find_legacy_user(suffix: nil)
    username = User.standardize_login(user_data.user_name, suffix: suffix)

    user = User.find_by_login(username)
    if user
      return [nil, ORGANIZATION_CONFLICT] if user.organization?
      [user, nil]
    end
  end

  # Internal: Provision a user
  #
  # user - if user is passed in the user will not be created, just some of the code will be used
  #
  # Returns Result object
  def provision_user(user: nil)
    return self.class.success_user_status(user) unless user.nil?

    default_opts = {}
    default_opts["email"] = user_data.primary_email unless user_data.primary_email.nil?
    user, message = create_user(user_data.user_name, user_data, user_data.admin?, default_opts)

    return self.class.create_user_status(message) if message
    self.class.success_user_status(user)
  end

  # Internal: a hook for additional processing before user update is executed
  #
  # user - a user to execute additional deprovisioning for
  #
  # Returns Result object
  def deprovision_user(user)
    self.role_reconciler_operation = :deprovision
    self.class.success_user_status(user)
  end

  # Internal: User reconciliation from base
  #
  # user            - A user that is attached to an id if id was provided
  # identity        - The identity to update
  #
  # Returns Result object
  def reconcile_user(
    user:,
    identity:
  )
    # reconcile user data if provisioning for this mapper is enabled
    if user && mapper.provisioning_enabled?(target: target)
      result = update_user(user: user, reason: @operation)
      return result unless result.success?
    end

    self.class.success_identity_status(identity)
  end

  # Public: Checks if the user's profile needs to be cleared due to GDPR
  #
  # Returns true if the user's profile needs to be cleared
  def clear_profile(reason)
    # For the Open SCIM API initiative, identity attributes for Open SCIM API user agents need to be preserved for suspended users
    # Open SCIM API user agents will evaluate false here and the profile won't be cleared
    return true if reason == :suspend && Business.scim_provider_type == :okta
    reason == :delete
  end

  # Internal: User update callback after success authentication
  #
  # user            - A user that is attached to an id if id was provided
  # reason          - reason for the reconciliation
  #         values are :provision, :update
  #
  # Returns result object
  def update_user(
    user:,
    reason:
  )
    # always returns result with no errors
    Platform::Provisioning::Result.success
  end

  # Internal: User update callback after scim delete
  #
  # Removes emails, avatars, ssh keys and gpg keys of the user account
  #
  # Returns nothing.
  def cleanup_deprovisioned_user(user, identity: nil)
    cleanup_deploy_keys = GitHub.flipper[:external_identity_cleanup_deploy_keys].enabled?(identity&.provider&.business)
    ExternalIdentity.cleanup_user(user, deploy_keys: cleanup_deploy_keys)
  end

  # Internal: Check circumstances in which an external identity created can be link to an existing user
  #
  # user            - A user that is attached to an id if id was provided
  # identity        - The identity to update
  #
  # Returns a boolean
  def valid_user_to_link_identity?(
    user:,
    identity:
  )
    # link to an existing SAML identity
    return true if user && identity.user == user

    # allow linking to a new identity unless user already has a linked identity
    provider = identity.provider
    existing_identity = ExternalIdentity.by_provider(provider).not_deleted.linked_to(user).first

    # allow linking to an existing user if:
    # - This is a new, unlinked identity
    # - There is no existing identity linked to the user
    return true if user && identity.user.nil? && existing_identity.nil?

    false
  end

  # Internal: Invite or notify identity flow, override if required
  #
  # identity        - The identity to send invite or notification to
  # inviter_id      - The ID of the user sending the invitation. Useful when
  #                   updating a pending invitation
  # inviter_type    - The type of the actor sending the invitation (defaults to User).
  #
  # Returns Result record
  def invite_or_notify_identity(
    identity:,
    inviter_id:,
    inviter_type:
  )
    self.class.success_identity_status(identity)
  end

  # Internal: Create an identity membership after the invitation has been received
  #
  # identity        - The identity to create a membership for
  # sso_invitation_token - (optional) The ID of the Organization::Invitation being accepted
  #                   on behalf of the user.
  #
  # Returns Result record
  def create_identity_membership(
    identity:,
    sso_invitation_token:
  )
    self.class.success_identity_status(identity)
  end

  # Internal: Save current identity record and process errors if any
  #
  # identity        - The identity to update
  # user            - (optional) The User the identity is linked to.
  #
  # Returns Result object
  def save_identity(
    identity,
    user: nil
  )
    if identity.save
      self.class.success_identity_status(identity)
    else
      # there was an issue saving the identity
      messages = identity.errors.full_messages

      Platform::Provisioning::Result.new \
        errors: messages.map { |m| Platform::Provisioning::Error.invalid_identity(message: m) }
    end
  end

  # Protected: A hook trigger method that will be executed before provisioned identity is saved
  #
  # Returns Result object
  def before_provision_identity(identity:, user:, actor_id: nil)
    User.transaction do
      begin
        # set the audit operation
        @operation = push_to_context(operation: PROVISION)

        # create or find an existing user
        # each provisioner can modify this behavior to suite the needs
        result = find_or_provision_user(identity: identity)
        next result unless result.success?

        user = result.provisioned_user
        identity.user = user

        if user&.suspended?
          @operation = push_to_context(operation: UNSUSPEND)

          next self.class.internal_error_status unless actor = User.find_by_id(actor_id)
          result = user.unsuspend(
            "has been provisioned via SCIM",
            actor: actor
          )
          next self.class.internal_error_status unless result
        end

        # after the user has been created or found it can be reconciled
        # with the user data (override if it is required)
        if user
          result = reconcile_user(user: user, identity: identity)
          next result unless result.success?
        end

        # check if the user is valid
        next self.class.create_user_status unless user.nil? || user.valid?

        self.class.success_identity_status(identity)
      rescue ActiveRecord::RecordInvalid
        # this is a just-in-case rescue, since we check for user.valid? before saving
        self.class.internal_error_status
      end
    end
  end

  # Protected: A hook trigger method that will be executed after provisioned identity is saved
  #
  # Returns Result object
  def after_provision_identity(identity:, user:, actor_id:, inviter_type:)

    # A flow to run identity invitation (override if it is required)
    result = invite_or_notify_identity(identity: identity, inviter_id: actor_id, inviter_type: inviter_type)
    return result unless result.success?

    self.class.success_identity_status(identity)
  end

  # Protected: A hook trigger method that will be executed before updated identity is saved
  #
  # Returns Result object
  def before_update_identity(identity:, user:, actor_id: nil, reconcile_user: true)
    User.transaction do
      begin
        # second par of suspension at this time user should already be suspended
        if !user_data.active?
          @operation = push_to_context(operation: SUSPEND)

          # do not suspend the user, just mark identity as disabled
          result = identity.disable
          next self.class.internal_error_status unless result

          # a hook to run a deprovisioning before updates to a user
          result = deprovision_user(user)
          next result unless result.success?
        # only unsuspend users - suspension is done outside of this transaction
        elsif identity.user&.suspended?
          @operation = push_to_context(operation: UNSUSPEND)

          next self.class.internal_error_status unless actor = User.find_by_id(actor_id)
          result = user.unsuspend(
            "has been provisioned via SCIM",
            actor: actor
          )
          next self.class.internal_error_status unless result

          result = provision_user(user: user)
          next self.class.internal_error_status unless result

          result = identity.enable
          next self.class.internal_error_status unless result

        # otherwise it is a normal update of a user
        else
          @operation = push_to_context(operation: UPDATE)
        end

        # after the user has been created or found it can be reconciled
        # with the user data (override if it is required)
        if reconcile_user
          result = reconcile_user(user: user, identity: identity)
          next result unless result.success?
        end

        # check if the update was successful and the user is valid
        next self.class.update_user_status unless user.valid?

        self.class.success_identity_status(identity)
      rescue ActiveRecord::RecordInvalid
        # this is a just-in-case rescue, since we check for user.valid? before saving
        self.class.internal_error_status
      end
    end
  end

  # Protected: A hook trigger method that will be executed after updated identity is saved
  #
  # Returns Result object
  def after_update_identity(identity:, user:, actor_id:, sso_invitation_token:)

    # A hook to create user memberships, this is part of an invitation flow
    result = create_identity_membership(identity: identity, sso_invitation_token: sso_invitation_token)
    return result unless result.success?

    unless user_data.active?
      if clear_profile(:suspend)
        # remove all of the attribute records when a user is deleted
        identity.identity_attribute_records.delete_all
      end
    end

    self.class.success_identity_status(identity)
  end

  # Protected: A hook trigger method that will be executed before deprovisioned identity is saved
  #
  # Returns Result object
  def before_deprovision_identity(identity:, user:)
    User.transaction do
      begin
        @operation = push_to_context(operation: DELETE)

        result = identity.disable
        next self.class.internal_error_status unless result

        result = identity.mark_deleted
        next self.class.internal_error_status unless result

        if user
          # a hook to run a deprovisioning before updates to a user
          result = deprovision_user(user)
          next result unless result.success?

          # update user data
          result = reconcile_user(user: user, identity: identity)
          next result unless result.success?
        end

        self.class.success_identity_status(identity)
      rescue ActiveRecord::RecordInvalid
        # this is a just-in-case rescue, since we check for user.valid? before saving
        self.class.internal_error_status
      end
    end
  end

  # Protected: A hook trigger method that will be executed after deprovisioned identity is saved
  #
  # Returns Result object
  def after_deprovision_identity(identity:, user:, actor_id:)
    cleanup_deprovisioned_user(user, identity: identity)

    # TODO: this can be removed since it is done in before_deprovision_identity identity.mark_deleted
    # remove all of the attribute records when a user is deleted
    identity.identity_attribute_records.delete_all

    self.class.success_identity_status(identity)
  end

  # private methods
  private

  # Private: Starts a job that refreshes a user's cached contributions
  #
  # Returns nothing
  def start_user_contribution_cache_refresh_job(user)
    options = { rebuild_contributions: user_data.rebuild_contributions }

    UserContributionCacheRefreshJob.perform_later(user.id, options) if options.select { |_, v| v }.any?
  end

  # Private: Suspends a user tied to the external identity
  #
  # identity        - The identity to update
  # actor           - a user suspending this identity
  # message         - (optional) override for a suspension message
  #
  # Returns Result record
  def suspend_user(
    identity:,
    actor:,
    message: nil
  )
    return self.class.identity_not_found_error_status unless identity.present?
    return self.class.internal_error_status unless user = identity.user
    return self.class.internal_error_status unless actor.present?

    # check if the user is already suspended
    return self.class.success_identity_status(identity) if user.suspended?

    set_context(identity: identity, user_id: identity.user_id)
    # set the audit operation
    push_to_context(operation: SUSPEND)

    User.transaction do
      result = user.suspend(
        message ||= "has been suspended via SCIM",
        actor: actor,
        hard_flag: true,
        instrument_abuse_classification: false,
      )

      next self.class.internal_error_status unless result
      next self.class.success_identity_status(identity)
    end
  end

  # Private: Saves identity and yields it to a block if given
  #
  # identity        - The identity to update
  # user_id         - The ID of the User the identity is linked to.
  # user            - A user that is attached to an id if id was provided
  #
  # Returns Result record
  def execute_save_identity(
    identity:,
    user: nil,
    before_save:,
    after_save:
  )
    result = nil

    ExternalIdentity.transaction do
      # set the appropriate data in the external identity record
      # needs to be done before the context is set
      mapper.set_user_data(identity: identity, user_data: user_data)

      unless identity.valid?
        result = if identity.errors.size == 1 && identity.errors.first.attribute == :base
          self.class.login_conflict_status
        else
          messages = identity.errors.full_messages
          Platform::Provisioning::Result.new \
            errors: messages.map { |m| Platform::Provisioning::Error.bad_request_error(message: m) }
        end

        self.class.rollback_unless_success(result)
      end

      set_context(identity: identity, user_id: user&.id)

      result = before_save.call(identity, user)
      self.class.rollback_unless_success(result)

      user = result.user if user.nil?
      identity.user = user

      result = save_identity(identity, user: user)
      self.class.rollback_unless_success(result)

      result = after_save.call(identity, user)
      self.class.rollback_unless_success(result)

      # Add an audit log event
      case @operation
      when :unsuspend, :provision
        identity.instrument_provision(action: @operation)
      when :delete, :suspend
        identity.instrument_deprovision(action: @operation)
      when :update
        identity.instrument_update
      end
    end

    result
  end

  # Private: A method to execute save for provisioned identity.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_provisioned_identity(identity:, user:, inviter_id:, inviter_type:)
    execute_save_identity(
      identity: identity,
      user: user,
      before_save: -> (in_identity, in_user) {
        before_provision_identity(identity: in_identity, user: in_user, actor_id: inviter_id)
      },
      after_save: -> (in_identity, in_user) {
        after_provision_identity(identity: in_identity, user: in_user, actor_id: inviter_id, inviter_type: inviter_type)
      }
    )
  end

  # Private: A method to execute save for updated identity.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_updated_identity(identity:, user:, actor_id:, sso_invitation_token:, reconcile_user: true)
    execute_save_identity(
      identity: identity,
      user: user,
      before_save: -> (in_identity, in_user) {
        before_update_identity(identity: in_identity, user: in_user, actor_id: actor_id, reconcile_user: reconcile_user)
      },
      after_save: -> (in_identity, in_user) {
        after_update_identity(identity: in_identity, user: in_user, actor_id: actor_id, sso_invitation_token: sso_invitation_token)
      }
    )
  end

  # Private: A method to execute save for deprovisioned identity.
  #       Hiding the implementation from the user.
  #
  # Returns Result object
  def save_deprovisioned_identity(identity:, user:, actor_id:)
    execute_save_identity(
      identity: identity,
      user: user,
      before_save: -> (in_identity, in_user) {
        before_deprovision_identity(identity: in_identity, user: in_user)
      },
      after_save: -> (in_identity, in_user) {
        after_deprovision_identity(identity: in_identity, user: in_user, actor_id: actor_id)
      }
    )
  end

  # Private: Set the current context for logging purposes
  #
  # identity        - an external identity record to set
  # user_id         - a user id this context is tied to
  #
  # Returns nothing
  def set_context(
    identity:,
    user_id:
  )
    context = {
      external_identity: identity,
      identity_mapper: mapper.to_s,
      linked_user_id: user_id,
      target: target,
    }

    # Audit log data
    GitHub.context.push context
    Audit.context.push context
  end

  # Internal: Push operation to context
  #
  # operation        - an operation to setup in an auditing context
  #
  # Returns operation pushed
  def push_to_context(operation:)
    # Audit log data
    GitHub.context.push operation: operation
    Audit.context.push operation: operation

    operation
  end
end
