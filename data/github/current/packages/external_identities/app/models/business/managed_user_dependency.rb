# typed: false
# frozen_string_literal: true

module Business::ManagedUserDependency
  include GitHub::Authentication::UserHandler
  extend T::Helpers

  # Raised when an attempt to demote the first emu owner is made.
  class CannotRemoveFirstEmuOwnerError < StandardError; end

  ADMIN_SUFFIX = "admin"

  # duplicated from app/api/scim/base_scim.rb so the scim tests run without PRELOAD=1
  AAD_USER_AGENT = "Microsoft Azure AD SCIM provisioning".downcase
  OKTA_USER_AGENT = "Okta SCIM client".downcase
  PING_FEDERATE_USER_AGENT = "Apache-HttpClient".downcase # PingFederate does not send a very specific user agent, but this should be fine

  SCIM_PROVIDER_TYPE = {
    AAD_USER_AGENT => :azure_ad,
    OKTA_USER_AGENT => :okta,
    PING_FEDERATE_USER_AGENT => :ping_federate
  }

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Public: Is this business configured as enterprise managed user provisioning enabled business
  #
  # Returns a Boolean
  def enterprise_managed_user_enabled?
    enterprise_managed?
  end

  # Repository colllaborators are the **EMU** flavor of Outside collaborators, and consists of EMUs assigned access
  # to repository resources, where the EMU is not a member of the organization that owns the repository.
  def emu_repository_collaborators_enabled?
    enterprise_managed_user_enabled?
  end

  # Ability to manage EMU repository collaborators policy (dictate which users can invite collaborators, default is all)
  def emu_repository_collaborators_policy_enabled?
    emu_repository_collaborators_enabled?
  end

  def enterprise_managed_user_and_saml_sso_enabled?
    saml_sso_enabled? && enterprise_managed_user_enabled?
  end

  def enterprise_managed_user_and_external_provider_enabled?
    external_provider_enabled? && enterprise_managed_user_enabled?
  end

  # Public: Creates a user account and adds the user as an owner to the enterprise
  #
  # email - email of the admin user who is being invited
  # actor - user who is performing the action
  # send_email_notification - whether to send email notifications to the user, defaults to true
  #
  # Returns the user if the user was successfully created and added as an owner to the enterprise
  def create_and_add_first_emu_owner(email:, actor:, send_email_notification: true, auto_verify_email: true)
    raise ArgumentError, "Invalid email" if email.nil? || !User.valid_email?(email)
    raise Business::UnableToCreateAdminUserError, "Unable to add admin user account in non enterprise managed business." unless enterprise_managed_user_enabled?
    raise Business::UnableToCreateAdminUserError, "Unable to add admin user account for SSO enabled enterprise." if self.external_provider_enabled?

    admin_user = find_first_emu_owner
    if admin_user
      raise Business::AdminAlreadyExistsError, "User #{admin_user.login} is already an owner of #{self.name}, and there can be only one non-IdP managed owner."
    else
      primary_email = add_emu_shortcode_to_emails(email, first_enterprise_owner: true)

      User.transaction do
        default_opts = {
          "email" => primary_email,
          "force_enterprise_managed" => true,
          "skip_reserved_domain" => actor&.feature_enabled?(:emu_owner_bypass_reserved_domain),
          "login_suffix" => ADMIN_SUFFIX,
        }
        default_opts["business_id"] = id if GitHub.multi_tenant_enterprise?
        admin_user, message = create_user(self.shortcode, nil, false, default_opts)

        if message
          raise Business::UnableToCreateAdminUserError, "Unable to create user for #{email} to add as an admin to the enterprise: #{message}"
        end

        # set the profile email, it will be set to original primary email
        profile = if admin_user.persisted?
          admin_user.find_or_create_profile
        else
          admin_user.build_profile
        end
        profile.email = email
        profile.save

        # Mark the primary email we have just created for the user as verified
        if auto_verify_email
          admin_user.emails.first.mark_as_verified
        end

        # Toggle visibility of a primary email
        # Hiding primary_email will force commits to use stealth email
        # which was not created due to issues with duplicate emails
        admin_user.emails.first.primary_role.toggle_visibility
        admin_user.emails.first.save

        self.add_owner(admin_user, actor: actor, send_email_notification: send_email_notification)
        admin_user
      end
    end
  end

  # Public: Resets the first owner account password, sending a new invitation
  #
  # send_email_notification - whether to send email notifications to the user, defaults to true
  #
  # Returns the user if the user was successfully updated
  def reset_first_emu_owner(email: nil, send_email_notification: true)
    admin_user = find_first_emu_owner
    if !admin_user
      raise Business::UnableToFindExistingAdminUserError, "Unable to reset admin for the enterprise"
    end

    send_admin_added_email_notification(role: :owner, admin: admin_user)
    admin_user
  end

  # Public: Adds a +shortcode to an email for an emu user.  Non-emu user will return passed in email.
  #
  # Returns string email
  def add_emu_shortcode_to_emails(emails, first_enterprise_owner: false)
    return emails unless enterprise_managed_user_enabled?

    User::EnterpriseManagedDependency.add_shortcode(emails, self, first_enterprise_owner: first_enterprise_owner)
  end

  # Public: Removes a +shortcode from an email for an emu user.  Non-emu user will return passed in email.
  #
  # Returns string email
  def remove_shortcode(email, first_enterprise_owner: false)
    return email unless enterprise_managed_user_enabled?

    User::EnterpriseManagedDependency.remove_shortcode(email, self, first_enterprise_owner: first_enterprise_owner)
  end

  # Public: Returns a user if there exists an admin user account for enterprise
  #
  # Returns user or nil.
  def find_first_emu_owner
    return unless enterprise_managed_user_enabled?

    admin_username = User.standardize_login(self.shortcode, suffix: ADMIN_SUFFIX)
    admin_user = User.find_by_login admin_username

    admin_user if self.owner?(admin_user)
  end

  # Public: Returns all owners of the enterprise except for the first enterprise owner
  #
  # Returns list of users
  def find_emu_owners_except_first
    return [] unless enterprise_managed_user_enabled?

    self.owners.reject { |user| is_first_emu_owner?(user: user) }
  end

  # Public: Return true if the user is the first enterprise owner in the business
  # false otherwise
  #
  # Return Boolean
  def async_first_enterprise_owner?(user:)
    return Promise.resolve(false) if user.nil?
    return Promise.resolve(false) unless user.user?
    return Promise.resolve(false) unless enterprise_managed_user_enabled?
    return Promise.resolve(false) unless self.owner?(user)
    return Promise.resolve(false) if business_user_account_for(user).nil?
    user.async_external_identities.then do |external_identities|
      return Promise.resolve(false) if external_identities.present?
    end

    user_login = user.login
    emu_admin_login = User.standardize_login(self.shortcode, suffix: ADMIN_SUFFIX)

    Promise.resolve(user_login == emu_admin_login)
  end

  # Public: Return true if the user is the first admin user
  # false otherwise.
  #
  # Returns boolean
  def is_first_emu_owner?(user:)
    return false if user.nil?
    return false unless user.user?
    return false unless enterprise_managed_user_enabled?
    return false unless self.owner?(user)
    return false if business_user_account_for(user).nil?
    return false if user.external_identities.present?

    user_login = user.login
    emu_admin_login = User.standardize_login(self.shortcode, suffix: ADMIN_SUFFIX)

    user_login == emu_admin_login
  end

  # Public: Nullify all shares_contributions_with UserSetting attributes for the users of the business
  def nullify_shares_contributions_with_user_setting
    # Find every user in this business who has a non-null shares_contributions_with UserSetting and set it to null
    UserSettings.where(user_id: self.user_accounts.collect(&:user_id))
      .where.not(shares_contributions_with: nil)
      .update_all(shares_contributions_with: nil)
  end

  def block_removal_of_first_emu_owner(user)
    return unless enterprise_managed_user_enabled?
    error_message = "First EMU owners cannot be removed"
    raise CannotRemoveFirstEmuOwnerError.new(error_message) if user.is_first_emu_owner?
  end

  sig { returns(T::Array[Integer]) }
  def guest_collaborator_ids
    return [] unless enterprise_managed? && external_provider

    # At one point in time organization_member_ids was passed into the query below
    # https://github.com/github/github/pull/362256 showed that this ruby side union was faster
    # This is still somewhat slow for large customers, so please benchmark any changes
    ExternalIdentity.by_provider(external_provider).where(guest_collaborator: true).pluck(:user_id) & organization_member_ids
  end

  sig { returns(T::Boolean) }
  def idp_cap_for_web_enabled?
    return false unless enterprise_managed_user_enabled?
    return false unless oidc_enabled?
    return false unless idp_based_ip_allowlist_configuration?

    # We want to make sure that this method returns false unless the customer has specifically enabled the feature
    idp_ip_allowlist_for_web_configurable_enabled?
  end

  module ClassMethods
    # Public: Return the enterprise managed business the provided resource belongs to
    # Currently only supports the following types:
    #   Organization
    #   User
    #   Repository
    #
    # Returns nil if the resource is not provided
    # or does not belong to an enterprise managed business
    def enterprise_managed_business_for(resource:)
      return unless resource.present?

      case resource
      when Organization
        resource.business if resource.enterprise_managed_user_enabled?
      when User
        resource.enterprise_managed_business
      when Repository
        owner = resource.owner

        if owner.is_a?(Organization)
          owner.business if owner.enterprise_managed_user_enabled?
        else # User
          owner&.enterprise_managed_business
        end
      else
        nil
      end
    end

    # Find the scim provider type based on the provided user_agent or the user_agent in the context
    # Returns nil if the user_agent is nil
    # Otherwise returns one of the following:
    #   :azure_ad
    #   :okta
    #   :ping_federate
    #   :open_scim
    def scim_provider_type(user_agent: GitHub.context[:user_agent])
      return nil if user_agent.nil?

      # Use `include?` to perform a substring check on the user_agent.
      # Whichever user agent substring is included in the user_agent will be returned in the first line
      # and then used to key into the SCIM_PROVIDER_TYPE hash.
      # ex. if user_agent is "Okta SCIM client 1.0.0" this method will return :okta
      agent = SCIM_PROVIDER_TYPE.keys.find { |ua| user_agent.downcase.include?(ua) }
      SCIM_PROVIDER_TYPE[agent] || :open_scim
    end
  end
  mixes_in_class_methods(ClassMethods)

  private

  # Private: Remove first EMU owner for enterprise manged business when business is deleted
  def remove_first_emu_owner
    return unless enterprise_managed_user_enabled?

    first_owner = find_first_emu_owner

    first_owner&.async_destroy(skip_permitted_check: true)
  end
end
