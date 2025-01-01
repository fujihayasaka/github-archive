# typed: true
# frozen_string_literal: true

# This is an extension class for GitHub Enterprise Server SCIM identity provisioning.  Any extension methods can
# be coded here and hooked up as stubs in the base identity provisioner.
class Platform::Provisioning::EnterpriseServerSCIMIdentityProvisioner < Platform::Provisioning::BaseIdentityProvisioner
  # Internal: Find user and check for errors, username will be standardized
  #    so not search by email is necessary
  #
  # Returns a tuple user or error message
  def find_legacy_user(suffix: nil)
    user, message = super

    return user, message if message.present?

    if user_data.name_id.present?
      # If the earlier look up succeeded, the normalized login is already
      # taken. Bail out and inform the user of the clash.
      return user, LOGIN_CONFLICT if user&.saml_mapping.present? &&
        user&.saml_mapping.name_id != user_data.name_id && user&.saml_mapping.name_id != user_data.user_name
    end

    [user, message]
  end

  # Internal: User reconciliation.
  #
  # user            - A user that is attached to an id if id was provided
  # identity        - The identity to update
  #
  # Returns Result object
  def reconcile_user(
    user:,
    identity:
  )

    # reconcile user data if user exists
    if user
      result = update_user(user: user, reason: @operation)
      return result unless result.success?
    end

    self.class.success_identity_status(identity)
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
    result = Platform::Provisioning::UserDataReconciler.reconcile(
      user,
      user_data,
      reason: reason,
      # set private instance processing for EMU
      flags: {
        is_enterprise_server: false, # needs to execute GitHub private instance provisioning flow
        reconcile_methods: !mapper.provisioning_enabled?(target: target) ? [] : Platform::Provisioning::UserDataReconciler::RECONCILER_METHODS,
        clear_profile: clear_profile(reason),
      },
    )

    if result.has_fatal?
      return Platform::Provisioning::Result.new(errors: result.error_values)
    end

    # just check for fatal email (when primary email is taken it will be set)
    if result.errors[:emails]&.fatal?
      return Platform::Provisioning::Result.new(errors: result.error_message(:emails))
    end

    # always returns result with no errors
    Platform::Provisioning::Result.success
  end

  # Internal: Provision a user
  #
  # user - if user is passed in the user will not be created, just some of the code will be used
  #
  # Returns Result object
  def provision_user(user: nil)
    if user.nil?
      user, message = create_user(user_data.user_name, user_data)

      return self.class.create_user_status(message: message) if message

      # Mark the primary email we have just created for the user as verified
      if user.emails.present?
        user.emails.first.mark_as_verified
        user.emails.first.save
      end
    end

    self.class.success_user_status(user.reload)
  end

  # Protected: A hook trigger method that will be executed after provisioned identity is saved
  #
  # Returns Result object
  def after_provision_identity(identity:, user:, actor_id:, inviter_type:)
    result = super
    return result unless result.success?

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    name_id = user_data.name_id
    unless name_id.nil?
      name_id_format = user_data.name_id_metadata["Format"]
      mapping = find_saml_mapping(name_id, user_data.user_name, name_id_format)

      if mapping
        if has_custom_username_attribute?
          mapping.migrate_mapping!(name_id, user_data.user_name)
        end
      else
        # Create saml mapping
        map_saml_entry(name_id, name_id_format, user.id)
      end
    end

    self.class.success_identity_status(identity)
  end

  # Protected: A hook trigger method that will be executed after updated identity is saved
  #
  # Returns Result object
  def after_update_identity(identity:, user:, actor_id:, sso_invitation_token:)
    result = super
    return result unless result.success?

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    name_id = user_data.name_id
    unless name_id.nil?
      name_id_format = user_data.name_id_metadata["Format"]
      mapping = find_saml_mapping(name_id, user_data.user_name, name_id_format)

      if mapping && has_custom_username_attribute?
        mapping.migrate_mapping!(name_id, user_data.user_name)
      end
    end

    self.class.success_identity_status(identity)
  end

  def after_deprovision_identity(identity:, user:, actor_id:)
    result = super
    return result unless result.success?

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    self.class.success_identity_status(identity)
  end

  private

  # determine if the running instance is configured to send SamlRequests with nameid-format=unspecified
  def name_id_format_unspecified?
    name_id_format = GitHub.auth.configuration[:name_id_format]
    return true unless name_id_format.present? # if not set, it defaults to unspecified
    name_id_format == "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
  end

  def has_custom_username_attribute?
    attribute_mappings[:user_name].present?
  end

  # Mapping from name of attribute to idP configured attribute name. This
  # will be replaced with constant values rather than configurable values.
  def attribute_mappings
    GitHub.auth.attribute_mappings
  end

  # Public - Create a mapping between the user and the SAML NameID or
  # claim/name or claim/email address in the case of a transient NameID and
  # keep a record of this.
  # It also updates the mapping when it exists.
  #
  # name_id: is the raw SAML NameID attribute or claim/name or claim/email address from the SAML response.
  # name_id_format: is the format of the SAML response.
  # user_id: is the ID of the logged in User.
  #
  # Returns true if the mapping was created.
  def map_saml_entry(name_id, name_id_format, user_id)
    SamlMapping.by_name_id_and_name_id_format(name_id, name_id_format) || SamlMapping.create(user_id: user_id, name_id: name_id, name_id_format: name_id_format)
  rescue ActiveRecord::RecordNotUnique
    # we don't care if the insert fails due to dupe key violation
    true
  end

  # Strategy to find the user corresponding to the SamlResponse
  #
  # 1. find by name_id. nameid-format has to match
  # 2. find by login. nameid-format has to match
  # 3. To address https://github.com/github/github/issues/90447,
  #    relax checking by name-id-format if requests are sent with unspecified,
  #    1. find by name_id
  #    2. find by login
  def find_saml_mapping(name_id, login, name_id_format)
    result = SamlMapping.by_name_id_and_name_id_format(name_id, name_id_format)
    return result if result.present?
    result = SamlMapping.by_name_id_and_name_id_format(login, name_id_format)
    return result if result.present?
    # if instance is configured to send request with unspecified, relax the search
    if name_id_format_unspecified?
      result = SamlMapping.find_by(name_id: name_id)
      return result if result.present?
      result = SamlMapping.find_by(name_id: login)
      result if result.present?
    end
  end
end
