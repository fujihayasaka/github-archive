# typed: true
# frozen_string_literal: true

module User::EnterpriseManagedDependency
  extend T::Helpers

  requires_ancestor { User }

  ENTERPRISE_MANAGED_ATTRIBUTES = [:profile_name, :profile_email, :profile_company]
  ADMIN_SUFFIX = "admin"

  INVALID_UNDERSCORE_LOGIN = %w[pj_nitin up_the_irons]

  NON_ENTERPRISE_MANAGED_BUSINESS_ID = 0

  # allows the provisioner to force this User to be considered enterprise-managed
  attr_accessor :force_enterprise_managed

  attr_writer :login_suffix

  # Public: A method to remove a short code from an email for an EMU user.
  #
  # Works on a String
  #
  # This method is created as a class method rather than the instance method since in some cases
  # there might not be an instance of a user yet, since the converted email is used to look it up.
  #
  # Returns email address string
  def self.remove_shortcode(
    email,
    enterprise,
    user: nil,
    first_enterprise_owner: false
  )
    # covering nil cases for email and enterprise, just return
    return email if email.nil? || (enterprise.nil? && user.nil?)

    # return email for web committer email
    return email if GitHub.web_committer_email == email

    shortcode = enterprise.shortcode if enterprise
    if user&.is_enterprise_managed?
      shortcode ||= if user.is_first_emu_owner?
        first_enterprise_owner = true
        user.login.split("_")[0]
      else
        user.login.split("_")[1]
      end
    end

    # must not be an emu enterprise since it does not have a shortcode
    return email unless shortcode.present?

    if first_enterprise_owner
      email.sub(/\+#{shortcode}-admin/i, "")
    else
      email.sub(/\+#{shortcode}/i, "")
    end
  end

  # Public: A method to add a short code to an email for an EMU user.  This prevents reuse
  # of the same email with a different user, for edge cases where a user already exists for an
  # enterprise that might be converting to emu.
  #
  # Works on a String and an Array of Strings
  #
  # This method is created as a class method rather than the instance method since in some cases
  # there might not be an instance of a user yet, since the converted email is used to look it up.
  #
  # first_enterprise_owner - special case when the email is appended +shortcode-admin
  #
  # Returns email address string
  def self.add_shortcode(
    email,
    enterprise,
    first_enterprise_owner: false
  )
    # if email matches a web committer email, return the email
    return email if GitHub.web_committer_email == email
    # covering nil cases for email and enterprise, just return
    return email if email.nil? || enterprise.nil?

    shortcode = enterprise.shortcode
    # must not be an emu enterprise since it does not have a shortcode
    return email unless shortcode.present?

    case email
    when String
      add_shortcode_to_email(email, shortcode, first_enterprise_owner)
    when Array
      email.map { |e| add_shortcode_to_email(e, shortcode, first_enterprise_owner) }
    end
  end

  # Private: Does specific checks on an email and performs injection of a shortcode
  #
  # Returns String or an email is not a String
  def self.add_shortcode_to_email(email, shortcode, first_enterprise_owner)
    # return nil if nil email is passed in (Array case only)
    return nil if email.nil?

    # Check if email is a String
    return email unless email.kind_of?(String)

    # return email for web committer email
    return email if GitHub.web_committer_email == email || UserEmail.belongs_to_a_bot?(email)

    rep_shortcode = if first_enterprise_owner
      "+#{shortcode}-admin@"
    else
      "+#{shortcode}@"
    end

    # Check if the shortcode has already been added
    return email if email[rep_shortcode]

    # check for @ sign in an email split it and put it together with a plus sing and shortcode
    #
    # Example: swanson@parks.org --> swanson+parks@parks.org
    if email["@"]
      username, domain = email.split("@") # email addresses
      return email if username.nil? || domain.nil?
      return username + rep_shortcode + domain
    end

    email
  end

  private_class_method :add_shortcode_to_email

  # Public: Returns whether the user is enterprise managed, simplified check will only check
  #   the presence of an underscore in the handle since it is only allowed for emu users.
  #
  # Returns Boolean
  def is_enterprise_managed?
    return @force_enterprise_managed unless @force_enterprise_managed.nil?

    return false if organization?
    return false if bot?
    return false if login.nil?

    if GitHub.multi_tenant_enterprise?
      # Multi tenant EMU user will have business_id != NON_ENTERPRISE_MANAGED_BUSINESS_ID
      # Users in multi tenant with business_id = NON_ENTERPRISE_MANAGED_BUSINESS_ID
      # are system or admin users that don't belong to an EMU business
      return business_id != NON_ENTERPRISE_MANAGED_BUSINESS_ID
    end

    # Check for two users that have _ but are not EMU - only applies to dotcom EMUs
    return false if INVALID_UNDERSCORE_LOGIN.include?(login)

    # EMU user will have an underscore
    !!login["_"]
  end

  def is_emu_admin?
    return false unless self.is_enterprise_managed?

    business = T.must(business_user_accounts.first).business
    return if business.nil?

    business.owner?(self)
  end

  def is_emu_and_not_first_owner?
    self.is_enterprise_managed? && !self.is_first_emu_owner?
  end

  # Public: Check whether the EMU user is also an owner of any orgs inside the business
  #
  # Returns a boolean
  def is_emu_org_owner?
    return false unless self.is_enterprise_managed?
    business = business_user_accounts.first&.business
    return false if business.nil?

    orgs = business.organizations
    return false if orgs.empty?

    orgs.any? { |org| org.adminable_by?(T.cast(self, User)) }
  end

  # Public: Check whether the EMU user is considered a guest collaborator
  #
  # Returns a boolean
  def guest_collaborator?
    return false unless is_enterprise_managed?
    return false if external_identities.empty?

    T.must(external_identities.first).guest_collaborator?
  end

  # Determines if user is part of GHES with SCIM enabled, or enterprise managed business
  #
  # Returns a boolean
  def scim_managed_user?
    return false unless user?

    # It's possible for a user to be part of SCIM enabled single enterprise but uses basic auth
    if GitHub.global_business&.enterprise_server_scim_enabled?
      return GitHub.auth.external_user?(self)
    end

    is_enterprise_managed?
  end

  # Public: Is deletion of this user disabled because it is managed by an IdP?
  #
  # Returns true for EMU
  # Returns true for GHES with SCIM enabled
  # Returns false otherwise
  #
  # Returns Boolean.
  def managed_user_deletion_disabled?
    return true if self.is_enterprise_managed?

    # It's possible for a user to be part of SCIM enabled single enterprise but uses basic auth
    if GitHub.global_business&.enterprise_server_scim_enabled?
      return GitHub.auth.external_user?(self)
    end
    false
  end

  # Public: Return true if the user is the first admin user
  # false otherwise.
  #
  # Returns boolean
  def is_first_emu_owner?
    return false unless self.user?
    return false unless self.is_enterprise_managed?

    enterprise = enterprise_managed_business
    return false if enterprise.nil?

    user_login = self.login
    emu_admin_login = User.standardize_login(enterprise.shortcode, suffix: ADMIN_SUFFIX)
    return false unless user_login == emu_admin_login

    enterprise.owner?(self)
  end

  # Public: Returns true if the user is deprovisioned
  #
  # When there is no identity record present, the identity is considered to be suspended and deprovisioned.  This
  # can happen during IdP or tenant changes where external_identity records are deleted and never recreated since
  # the same user is never re-provisioned.
  #
  # When an EMU is being created, there will be no identity record until after the EMU is saved. In this
  # case, we want to return false.
  #
  # If the identity record is present return whether the disabled_at attribute is present or not
  def deprovisioned?
    # will return false for non-emu users
    return false unless is_enterprise_managed?

    identity = external_identities.first
    return persisted? ? true : false unless identity.present?
    identity.disabled_at?
  end

  # Public: Get the login suffix queried from the business
  #
  # An enterprise managed user will have exactly one BusinessUserAccount associated with an
  # enterprise managed user enabled Business.
  #
  # Sets and returns login_suffix from Business shortcode
  def login_suffix
    return @login_suffix unless @login_suffix.nil?

    enterprise = enterprise_managed_business
    return nil if enterprise.nil?

    @login_suffix = enterprise.shortcode
    @login_suffix
  end

  # Public: Removes a +shortcode from an email for an emu user.  Non-emu user will return passed in email.
  #
  # Returns string email
  def remove_shortcode(email, business: nil)
    User::EnterpriseManagedDependency.remove_shortcode(email, business, user: self)
  end

  # Public: Adds a +shortcode to an email for an emu user.  Non-emu user will return passed in email.
  #
  # Returns string email
  def add_emu_shortcode_to_emails(email, business: nil)
    return email unless is_enterprise_managed?

    business ||= enterprise_managed_business

    User::EnterpriseManagedDependency.add_shortcode(email, business, first_enterprise_owner: is_first_emu_owner?)
  end

  # Public: Returns the enterprise business associated with the user
  #
  # Returns a Business record
  def enterprise_managed_business
    async_enterprise_managed_business.sync
  end

  def async_enterprise_managed_business
    async_business_user_accounts.then do |business_user_accounts|
      next unless business_user_accounts.one?
      T.must(business_user_accounts.first).async_business.then do |business|
        next unless business&.enterprise_managed_user_enabled?
        business
      end
    end
  end

  # Public: This method is used to check if a user is allowed to create public repositories.
  # EMUs are not allowed to create public repositories.
  #
  # Returns a Boolean
  def public_repositories_available?
    # Unfortunately the methods are not homogeneous.
    # Calling org.is_enterprise_managed? on an EMU org will return false.
    # https://github.com/github/external-identities/issues/790
    is_enterprise_managed =
      case self
      when Organization
        enterprise_managed_user_enabled?
      when User
        is_enterprise_managed?
      end
    return true unless is_enterprise_managed

    false
  end

  # Public: This method is used to check if an EMU is attempting to create a public repo.
  # EMUs are not allowed to create public repositories.
  #
  # Returns a Boolean
  def emu_creating_public_repo?(visibility)
    return false if public_repositories_available?
    return false unless visibility.to_s == Repository::PUBLIC_VISIBILITY
    true
  end

  # Public: This method is used to update the first emu owner email to the new email.
  #
  # Returns a String
  def update_first_emu_owner_email(new_email)
    return "Email unchanged." unless is_first_emu_owner?
    return "Email unchanged." if new_email == profile_email

    trimmed_new_email = new_email.strip

    old_email = profile_email
    old_primary_user_email = primary_user_email&.email
    admin_profile = find_or_create_profile

    new_primary_user_email = User::EnterpriseManagedDependency.add_shortcode(trimmed_new_email, enterprise_managed_business, first_enterprise_owner: true)

    primary_email_status = User::SetPrimaryEmailStatus::SUCCESS
    profile_email_update_success = T.let(true, T::Boolean)

    transaction do
      primary_user_email = emails.build(email: new_primary_user_email)
      primary_user_email.mark_as_verified

      primary_email_status = set_primary_email(primary_user_email)

      # if the primary email update is not successful, we should not update the profile email
      next unless primary_email_status.success?

      admin_profile.email = trimmed_new_email
      unless admin_profile.save!
        profile_email_update_success = false
        raise ActiveRecord::Rollback
      end
    end

    return "Error updating admin profile" unless profile_email_update_success
    return primary_email_status.error unless primary_email_status.success?

    if remove_email(old_primary_user_email)
      "Email updated successfully.  Please note that the primary email address has been changed to '#{new_primary_user_email}'."
    else
      "Error removing old primary email address '#{old_primary_user_email}'."
    end
  end

  # Public: Verifies that the email is associated with the user account.  Right now only
  #         first emu owner accounts are verified.
  #
  # Returns Boolean
  def known_email?(email_address)
    return false if email_address.nil?
    return false unless user?
    return false unless is_first_emu_owner?

    return true if !!T.unsafe(emails.user_entered_emails).find_by_email(email_address)
    admin_email = User::EnterpriseManagedDependency.add_shortcode(email_address, enterprise_managed_business, first_enterprise_owner: true)
    !!T.unsafe(emails.user_entered_emails).find_by_email(admin_email)
  end

  def get_organization_ability(organization_id)
    Ability.user_direct_read_on_organization(
      actor_id: id,
      subject_id: organization_id,
    ).first
  end

  protected

  # Public: Returns whether the user is enterprise managed, this check is performed when the
  #   user is created and updated.
  #
  # An enterprise managed user will have exactly one BusinessUserAccount associated with an
  # enterprise managed user enabled Business.
  #
  # Returns Boolean
  def is_enterprise_managed_user?
    return @force_enterprise_managed unless @force_enterprise_managed.nil?

    enterprise = enterprise_managed_business
    @force_enterprise_managed = if enterprise.nil?
      false
    else
      enterprise.enterprise_managed_user_enabled?
    end
  end
end
