# typed: true
# frozen_string_literal: true

class Platform::Provisioning::EnterpriseManagedIdentityProvisioner < Platform::Provisioning::BaseIdentityProvisioner
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
        is_enterprise_server: false,
        is_emu: true,
        clear_profile: clear_profile(reason),
        skip_reserved_domain: true
      },
      # blank primary email generates a fatal error
      error_options: { primary_email_blank: true }
    )

    # return result and convert all errors to an array
    if result.has_fatal?
      return Platform::Provisioning::Result.new(errors: result.error_values)
    end

    # always returns result with no errors
    Platform::Provisioning::Result.success
  end

  # Internal: Find user and check for errors, username will be standardized
  #    so not search by email is necessary
  #
  # Returns a tuple user or error message
  def find_legacy_user(suffix: nil)
    super(suffix: target.shortcode)
  end

  # Internal: Provision a user
  #
  # user - if user is passed in the user will not be created, just some of the code will be used
  #
  # Returns Result object
  def provision_user(user: nil)
    if user_created = user.nil?
      profile_email = user_data.primary_email if user_data.primary_email.present?
      primary_email = target.add_emu_shortcode_to_emails(profile_email) if profile_email.present?
      default_opts = {
        "email" => primary_email,
        "force_enterprise_managed" => true,
        "login_suffix" => target.shortcode,
        "skip_reserved_domain" => true
      }
      default_opts["business_id"] = target.id if GitHub.multi_tenant_enterprise?

      begin
        user, message = create_user(user_data.user_name, user_data, user_data.admin?, default_opts)
      rescue ActiveRecord::RecordNotUnique => e
        return self.class.login_conflict_status(message: e.message)
      end

      return self.class.create_user_status(message: message) if message

      # set the profile email, it will be set to original primary email
      profile = if user.persisted?
        user.find_or_create_profile
      else
        user.build_profile
      end
      profile.email = profile_email
      profile.save

      # Mark the primary email we have just created for the user as verified
      user.emails.first.mark_as_verified

      # Toggle visibility of a primary email
      # Hiding primary_email will force commits to use stealth email
      # which was not created due to issues with duplicate emails
      user.emails.first.primary_role.toggle_visibility
      user.emails.first.save
    end

    # Attach a business user account to the user
    if user.valid? && user.enterprise_managed_business.nil?
      # It would be nice to use Business#add_user_accounts to handle this deduplication
      # but it requires that the external identity object already exists for a user.
      # When provisioning, the UserDataReconciler gets run before the external identity is created and the
      # reconciler needs the user to already be linked to the business in order to properly reconsile, so
      # we have to duplicate the email extraction logic here

      bua = target.enterprise_users_from_emails(user_data.emails).values.first
      if bua
        user.business_user_accounts << bua
      else
        user.business_user_accounts.create(business_id: target.id)
      end
    end

    self.class.success_user_status(user)
  end

  # Internal: Check circumstances in which an external identity created can be link to an existing user
  #
  # user            - A user that is attached to an id if id was provided
  # identity        - The identity to update
  #
  # Returns false when user is liked to an enterprise or has any external_identities linked
  def valid_user_to_link_identity?(
    user:,
    identity:
  )
    return false if user.enterprise_managed_business.nil?
    return false unless user.enterprise_managed_business == target
    return false if user.external_identities.any?
    true
  end

  # Protected: A hook trigger method that will be executed after provisioned identity is saved
  #
  # Returns Result object
  def after_provision_identity(identity:, user:, actor_id:, inviter_type:)
    result = super
    return result unless result.success?

    assign_user_to_bundled_license_assignment(user)

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    self.class.success_identity_status(identity)
  end

  # Protected: A hook trigger method that will be executed after updated identity is saved
  #
  # Returns Result object
  def after_update_identity(identity:, user:, actor_id:, sso_invitation_token:)
    result = super
    return result unless result.success?

    assign_user_to_bundled_license_assignment(user)

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    self.class.success_identity_status(identity)
  end

  # Protected: A hook trigger method that will be executed after deprovisioned identity is saved
  #
  # Returns Result object
  def after_deprovision_identity(identity:, user:, actor_id:)
    result = super
    return result unless result.success?

    result = role_reconciler.reconcile(identity: identity, actor_id: actor_id)
    return result if result && !result.success?

    self.class.success_identity_status(identity)
  end

  # Private: Queues a job to assign bundles license for user if business has VSS bundle licensing enabled
  #
  # Returns nothing
  def assign_user_to_bundled_license_assignment(user)
    return unless user
    return unless ActiveRecord::Base.connected_to(role: :reading) do
      target&.volume_licensing_enabled?
    end

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_later(
      business: target, user: user, emails: [user_data.user_name, user.profile_email]
    )
  end
end
