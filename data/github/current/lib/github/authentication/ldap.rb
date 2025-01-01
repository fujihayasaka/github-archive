# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    class LDAP < Default
      require "github/ldap"
      include UserHandler
      include GitHub::Telemetry::Logs::Loggable

      INVALID_CREDENTIALS_MESSAGE = "Invalid LDAP login credentials."

      # Hex value that represents an account disabled in Active Directory.
      ACCOUNT_DISABLED = 0x0002

      # Active Directory account control attribute.
      ACCOUNT_CONTROL_ATTR = :userAccountControl

      def name; "LDAP"; end

      def external?; true; end

      # Public: Determines if a given user is using LDAP authentication
      # or if they're using builtin authentication.
      #
      # If the user does not exist locally, assume we are asking about an
      # LDAP user whose account has not yet been created.
      #
      # user_of_login - The User itself or their login/email.
      #
      # Returns a Boolean.
      def external_user?(user_or_login)
        return true unless builtin_auth_fallback?

        user = User.reify(user_or_login)
        !!(user.nil? || user.ldap_mapping)
      end

      # Public: Returns any mapping information we have on hand, if any, for
      # external users.
      def external_mapping(user)
        user.ldap_mapping
      end

      def signup_enabled?; false end

      def two_factor_authentication_enabled?
        true
      end

      # LDAP supports builtin 2FA whether the user is using
      # builtin auth fallback or LDAP.
      def two_factor_authentication_allowed?(user)
        true
      end

      # Public: Whether Users can be renamed.
      #
      # Can be configured using the "user_renaming_enabled" advanced setting.
      # Users without an ldap mapping cannot be renamed.
      #
      # Returns true by default.
      def user_renaming_enabled?(user)
        case GitHub.config.get "user_renaming_enabled"
        when nil, "true"
          return false unless user && user.ldap_mapping
          true
        else
          false
        end
      end

      # Public: Whether changing user profile names via the UI is allowed or not.
      #
      # Returns false if LDAP Sync is enabled and the user is authenticated via LDAP
      def user_change_profile_name_enabled?(user)
        return false if profile_name_managed_externally? && user&.ldap_mapped?
        true
      end

      # Public: Whether changing emails via the UI is allowed or not.
      #
      # Returns false if LDAP Sync is enabled and the user is authenticated via LDAP
      def user_change_email_enabled?(user)
        return false if emails_managed_externally? && user&.ldap_mapped?
        true
      end

      # Public: Whether changing SSH keys via the UI is allowed or not.
      #
      # Returns false if LDAP Sync is enabled and the user is authenticated via LDAP
      def user_change_ssh_key_enabled?(user)
        return false if ssh_keys_managed_externally? && user&.ldap_mapped?
        true
      end

      # Public: Whether changing GPG keys via the UI is allowed or not.
      #
      # Returns false if LDAP Sync is enabled and the user is authenticated via LDAP
      def user_change_gpg_key_enabled?(user)
        return false if gpg_keys_managed_externally? && user&.ldap_mapped?
        true
      end

      # Public: Returns true if Profile Names are managed externally (LDAP Synced).
      def profile_name_managed_externally?
        GitHub.ldap_sync_enabled?
      end

      # Public: Returns true if Emails are managed externally (LDAP Synced).
      def emails_managed_externally?
        GitHub.ldap_sync_enabled? && GitHub.ldap_user_sync_emails
      end

      # Public: Returns true if SSH Keys are managed externally (LDAP Synced).
      def ssh_keys_managed_externally?
        GitHub.ldap_sync_enabled? && GitHub.ldap_user_sync_keys
      end

      # Public: Returns true if GPG Keys are managed externally (LDAP Synced).
      def gpg_keys_managed_externally?
        GitHub.ldap_sync_enabled? && GitHub.ldap_user_sync_gpg_keys
      end

      # Public: Attempts to authenticate a user via login and password. By
      # default authentication is done by the configured LDAP provider. If
      # builtin authentication fallback is enabled, we'll also attempt to
      # authenticate the user locally.
      #
      # login    - The user login String
      # password - The LDAP or local user password String.
      #
      # Returns a GitHub::Authentication::Result.
      def password_authenticate(login, password)
        if builtin_auth_fallback? && !external_user?(login)
          result = super(login, password)
          return result if result.success? || result.suspended_failure?
        end

        ldap_password_authenticate(login, password)
      end

      # Authenticates a user via LDAP then finds or creates the local user.
      #
      # Returns a GitHub::Authentication::Result.
      def ldap_password_authenticate(login, password)
        unless password.present?
          return GitHub::Authentication::Result.password_failure(
            message: "Invalid login credentials.", failure_reason: :invalid_login_credentials
          )
        end

        begin
          # Timeout slow LDAP authentication requests 0.5s before the configured timeout (defaults to 10s).
          GitHub::Timer.timeout(GitHub.ldap_auth_timeout - 0.5) do
            # check credentials against LDAP
            entry, message = ldap_authenticate(login, password)

            unless entry
              return GitHub::Authentication::Result.password_failure(message: message, failure_reason: :no_ldap_account_for_user)
            end

            # check whether LDAP entry is authorized
            ldap_authorization = ldap_authorization(entry)
            unless ldap_authorization.valid?
              return GitHub::Authentication::Result.password_failure(
                message: "Please contact your Enterprise administrator to request access.", failure_reason: :ldap_user_access_unauthorized
              )
            end

            user, message = find_or_create_user(login, entry)
            unless user
              return GitHub::Authentication::Result.password_failure(message: message, failure_reason: :error_creating_user_account_for_ldap_account)
            end

            # make sure we track the correct LDAP UID for this User account
            reconcile_fallback_uid(user, entry)

            # validate and reconcile access (auto-suspend)
            reconcile_access(user, ldap_authorization, reactivate_suspended_user: GitHub.reactivate_suspended_user?)

            if user.suspended?
              return GitHub::Authentication::Result.suspended_failure(
                message: "Your account has been suspended. Please contact your Enterprise administrator to request access.", failure_reason: :suspended_user_account_for_ldap_user
              )
            end

            # auto-promote
            reconcile_admin(user, entry)

            # success
            GitHub::Authentication::Result.success(user, message: message)
          end
        rescue Timeout::Error
          instrument "ldap.authenticate.timeout", login: login
          GitHub::Authentication::Result.password_failure(message: "The external authentication server failed to respond within #{GitHub.ldap_auth_timeout} seconds. Please try again or contact your GitHub Enterprise administrator if the problem persists.", failure_reason: :ldap_timeout)
        end
      end

      # Try to authenticate the login/password with one of the ldap domains configured.
      # It loops over the domains until it finds a valid user.
      # If there are no groups configured it returns the first user it finds.
      # If there are groups configured and exist in the domain it checks if the user is a member of any of the groups.
      #
      # login: is the login information set in the sign in form.
      # password: is the password information set in the sign in form.
      #
      # Return the user info in the ldap domain if the login/password are valid.
      # Returns nil if the login/password are invalid or if an error occurs
      #   contacting the LDAP server.
      def ldap_authenticate(login, password)
        instrument "ldap.authenticate_start", login: login
        GitHub::Authentication.logger.info("Searching for user entry", "code.namespace" => self.class.name, "code.function" => __method__, "gh.auth.login" => login)

        # To avoid attempting to bind to the same DN multiple time with the
        # same (invalid) password during a single call to ldap_authenticate, we
        # track which DNs we've tried. Otherwise, we'd usually attempt the same
        # ldap bind three times:
        # - ldap_authenticate_by_ldap_mapping attempts with the last known DN
        # - ldap_authenticate_by_login searches by username to find the DN and
        #                              attempts with that
        # - ldap_authenticate_by_login does the same thing again with the
        #                              fallback username, which may be the same
        #                              as the original username
        attempted = []

        instrument "ldap.authenticate", login: login do |payload|
          strategy.open do
            payload[:entry] = entry = find_ldap_mapping_by_login(login)

            user, message = ldap_authenticate_by_ldap_mapping(entry, login, password, attempted: attempted) if entry
            user, message = ldap_authenticate_by_login(login, password, attempted: attempted) unless user

            payload[:user]    = user
            payload[:message] = message

            [user, message]
          end
        end
      rescue Net::LDAP::Error, Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ECONNRESET, Errno::ENETUNREACH => e
        GitHub::Authentication.logger.error(e)
        instrument "ldap.authenticate_error", login: login, error: e
        [nil, "Unable to connect to the external authentication server. Please try again or contact your GitHub Enterprise administrator if the problem persists."]
      rescue Errno::ETIMEDOUT
        GitHub::Authentication.logger.error(e)
        instrument "ldap.authenticate.timeout", login: login
        [nil, "The external authentication server failed to respond. Please try again or contact your GitHub Enterprise administrator if the problem persists."]
      end

      # Authenticate users by mapping their dn in database and checking their password.
      #
      # entry: is the ldap entry resolved with the ldap mapping that we have in db.
      # login: is the login name to authenticate.
      # password: is the user password.
      # attempted: DNs that have already been attempted and should not be attempted again.
      #
      # Returns the entry if the login and password are valid.
      # Returns nil if the login/password are invalid.
      def ldap_authenticate_by_ldap_mapping(entry, login, password, attempted: [])
        GitHub::Authentication.logger.info("user mapped to ldap dn", "code.namespace" => self.class.name, "code.function" => __method__, "gh.auth.login" => login, "ldap.dn" => entry.dn)

        return nil if attempted.include?(entry.dn)
        attempted << entry.dn

        if valid_authentication_bind?(entry.dn, password)
          entry
        else
          nil
        end
      end

      # Internal: Returns array of attributes LDAP queries should fetch.
      def query_attributes
        ldap_profile.values + [ACCOUNT_CONTROL_ATTR.to_s]
      end

      # Authenticate users by searching in the ldap domains configured.
      #
      # login: is the login name to authenticate.
      # password: is the user password.
      # fallback: whether or not to try authenticating using the fallback_uid.
      # attempted: DNs that have already been attempted and should not be attempted again.
      #
      # Returns the entry if the login and password are valid.
      # Returns nil if the login/password are invalid.
      def ldap_authenticate_by_login(login, password, fallback: true, attempted: [])
        with_ldap_domains do |base_name, domain|
          GitHub::Authentication.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => __method__, "gh.auth.login" => login, "ldap.base" => base_name) do
            GitHub::Authentication.logger.info("Looking for ldap mapping")

            entry = domain.user?(login, attributes: query_attributes)
            if !entry
              GitHub::Authentication.logger.info("Invalid ldap username")
              next
            end

            next if attempted.include?(entry.dn)
            attempted << entry.dn

            return entry if valid_authentication?(base_name, domain, entry, login, password)
          end
        end

        # Fallback to check the original login in case the user changed it.
        return ldap_authenticate_by_fallback_uid(login, password, attempted: attempted) if fallback

        # Otherwise, fail due to invalid credentials.
        [nil, INVALID_CREDENTIALS_MESSAGE]
      end

      # Internal - Authenticate users by mapping fallback uid.
      # Corner case when users change their login and admins change ldap DNs.
      #
      # login: is the login name to search for the fallback uid.
      # password: is the user password.
      # attempted: DNs that have already been attempted and should not be attempted again.
      #
      # Returns the entry if the password is valid for the fallback uid.
      # Returns nil if there is not fallback uid for the user.
      # Returns nil if the login/password are invalid.
      def ldap_authenticate_by_fallback_uid(login, password, attempted: [])
        candidate = User.find_by_login(login)
        candidate ||= find_user_by_ldap_fallback_uid(login)
        return nil, INVALID_CREDENTIALS_MESSAGE unless candidate

        fallback_uid = candidate.ldap_fallback_uid
        return nil, INVALID_CREDENTIALS_MESSAGE unless fallback_uid

        ldap_authenticate_by_login(fallback_uid, password, fallback: false, attempted: attempted)
      end

      # Check if the credentials are valid for a domain.
      #
      # Returns true if we can bind the user in the ldap domain.
      # Return false otherwise.
      def valid_authentication?(base_name, domain, entry, login, password)
        valid = domain.auth(entry, password)

        unless valid
          GitHub::Authentication.logger.info("Invalid ldap credentials", "code.namespace" => self.class.name, "code.function" => __method__)
        end

        # Ensure the connection is bound with the admin service account, and
        # not the user that we bound as.
        strategy.bind

        valid
      end

      # Check if the credentials are valid for a domain.
      #
      # Returns true if bind is successful, false otherwise
      def valid_authentication_bind?(dn, password)
        valid = strategy.bind(method: :simple, dn: dn, password: password)
        unless valid
          GitHub::Authentication.logger.info("Invalid ldap credentials", "code.namespace" => self.class.name, "code.function" => __method__, "ldap.dn" => dn)
        end
        valid
      ensure
        # Ensure the connection is bound with the admin service account, and
        # not the user that we bound as.
        strategy.bind
      end

      # Internal: Check whether restricted access group membership needs to be
      # validated.
      #
      # Returns true if any restricted user groups are set.
      def validate_membership?
        !GitHub.ldap_user_groups.blank?
      end

      # Check if the user has a valid membership in the configured groups.
      #
      # entry: is the user's ldap information.
      #
      # Returns true if there are no groups configured.
      # Returns true if the user belongs to any of the groups configured.
      # Returns nil otherwise.
      def valid_membership?(entry)
        return true if authentication_groups.empty?

        # admin group doesn't count
        return true if !validate_membership?

        return true if membership_validator.perform(entry)
        GitHub::Authentication.logger.info("Membership not found", "code.namespace" => self.class.name, "code.function" => __method__, "ldap.dn" => entry.dn, "ldap.auth_groups" => authentication_groups)

        false
      end

      # Public: Reconciles access by suspending or unsuspending the User record.
      #
      # If a user can authenticate to LDAP and is allowed to access the GHE appliance,
      # they'll be unsuspended by default. (For historical reasons, this is the
      # opposite of the SAML and CAS default behavior).
      #
      # Admins can prevent unsuspension by setting `auth.reactivate-suspended` to false.
      #
      # user: User object to suspend/unsuspend
      # ldap_authorization: GitHub::LDAP::Authorization instance
      # reactivate_suspended_user: whether or not to unsuspend suspended user
      #
      # Returns true if user.unsuspend or user.suspend was successful
      # Returns false if user.unsuspend or user.suspend was unsuccessful
      # Returns nil otherwise.
      def reconcile_access(user, ldap_authorization, reactivate_suspended_user:)
        if ldap_authorization.valid?
          if user.suspended? && reactivate_suspended_user
            ActiveRecord::Base.connected_to(role: :writing) do
              user.unsuspend("is granted access in LDAP")
            end
          end
        elsif !user.suspended?
          ActiveRecord::Base.connected_to(role: :writing) do
            user.suspend("is not granted access in LDAP (#{ldap_authorization.state})")
          end
        end
      end

      # Default configuration for the LDAP adapter.
      # On Enterprise those values are set by environment variables.
      #
      # Returns a Hash with the default settings.
      def default_config
        {
          host: GitHub.ldap_host,
          port: GitHub.ldap_port,
          user_domain: GitHub.ldap_base,
          admin_user: GitHub.ldap_bind_dn,
          admin_password: GitHub.ldap_password,
          encryption: GitHub.ldap_method,
          tls_options: ldap_tls_options,
          search_domains: GitHub.ldap_base,
          search_strategy: GitHub.ldap_search_strategy,
          virtual_attributes: GitHub.ldap_virtual_attributes,
          recursive_group_search_fallback: GitHub.ldap_recursive_group_search_fallback,
          posix_support: GitHub.ldap_posix_support,
          uid: ldap_profile["uid"] || "uid",
        }
      end

      def ldap_tls_options
        { verify_mode: GitHub.ldap_tls_verify_mode  }
      end

      def ldap_profile
        @ldap_profile ||= {
          "uid"  => GitHub.ldap_profile_uid || "uid",
          "name" => GitHub.ldap_profile_name || "cn",
          "mail" => GitHub.ldap_profile_mail || "mail",
          "key"  => GitHub.ldap_profile_key || "sshPublicKey",
          "gpgkey" => GitHub.ldap_profile_gpg_key || "pgpKey",
        }
      end

      # Override standard user find to search by LDAP DN when available.
      def find_user(uid, entry)
        if mapping = LdapMapping.by_dn(entry.dn).where(subject_type: "User").first
          return mapping.subject
        end

        if user = find_user_by_ldap_fallback_uid(uid)
          user.map_ldap_entry(entry.dn)
          return user
        end

        # Special case: UIDs formatted as email addresses cause problems when
        # users login with the UID. Without this override, find_user assumes
        # the user is logging in with an email address instead of the UID.
        # This results in a non-match causing the create_user logic to try to
        # create the same user.
        # This specifically tests to see if the login and the UID are formatted
        # as email addresses in order to find the user, falling back to normal
        # methods otherwise.
        if uid["@"] && profile_info(entry, :uid).first["@"]
          login = User.standardize_login(uid)
          if user = User.find_by_login(login)
            if message = collision_with_existing_user?(uid, entry, user)
              return [nil, message]
            else
              user.map_ldap_entry(entry.dn)
              return user
            end
          end
        end

        # fall back to normal user lookup
        user, message = super

        message = collision_with_existing_user?(uid, entry, user) if user

        user = nil if message

        # ensure we map the LDAP entry
        user.map_ldap_entry(entry.dn) if user

        [user, message]
      end

      # Check for an incoming authentication request that improperly matches an existing user
      # This check covers the corner case of:
      #   - The user that's found has an LDAPMapping DN
      #   - AND the entry that was authenticated has a UID that doesn't match the user's fallback_uid
      #   - AND the user's LDAPMapping DN still exists in the directory
      #
      # See https://github.com/github/github/issues/149006 for more detail
      #
      # Returns an error message describing the collision, or nil
      def collision_with_existing_user?(uid, entry, user)
        # If the identified user doesn't have an ldap_mapping we can't check
        # the directory. This shouldn't happen for non-built-in users
        return unless user.ldap_mapping

        # We allow assumption of the account if the supplied password authenticates
        # by using the fallback_uid of the account, if the fallback_uid is in the directory.
        # This will fail if we are preventing "mona_lisa" from taking over "mona.lisa"
        return if user.ldap_mapping.fallback_uid == entry.uid

        # If the LDAP mapping associated with the found user is still in
        # the directory, but the authentication entry is different, then we can
        # consider it to be a collision between uids that standardize to the same login

        existing_dn_entry = strategy.domain(user.ldap_mapping.dn).bind
        if existing_dn_entry
          GitHub::Authentication.logger.info("uid will collide with an existing user", "code.namespace" => self.class.name, "code.function" => __method__, "ldap.dn" => entry.dn, "gh.auth.login" => user.login)
          "This login is already taken by an existing user. Please contact your administrator."
        end
      end

      # Search for a user by their LDAP fallback uid.
      #
      # uid: LDAP uid
      #
      # Returns nil if there is no ldap mapping for the fallback uid.
      # Returns the User if the User exists.
      def find_user_by_ldap_fallback_uid(uid)
        if mapping = LdapMapping.where(
            fallback_uid: uid, subject_type: "User").first
          mapping.subject
        end
      end

      # Create a user in the github database after signing in the first time.
      # This is called only if the user login doesn't exist already in the database.
      #
      # uid   - the user's login String.
      # entry - a Net::LDAP::Entry
      #
      # Returns a User object and a string with a message.
      def create_user(uid, entry)
        if ldap_mapping_present?(entry.dn)
          return nil, "Your LDAP DN already corresponds to another user."
        end

        user_opts = {}
        emails_info = profile_info(entry, :mail)

        # ensure we only try importing valid emails
        emails_info.select! { |email| email =~ User::EMAIL_REGEX }

        user_opts[:email] = emails_info.shift
        user_opts[:needs_ldap_memberships_sync] = true
        user_opts[:ldap_mapping] = LdapMapping.new(
          dn: entry.dn,
          fallback_uid: uid,
        )

        ActiveRecord::Base.connected_to(role: :writing) do
          user, message = super(uid, entry, is_admin?(entry), user_opts)
          return user, message unless user

          # Ensure that any changed attributes are cleared for subsequent after_commit callbacks
          user.reload

          create_profile(user, entry)
          create_emails(user, emails_info)
          create_public_keys(user, entry)
          create_gpg_keys(user, entry)

          user.enqueue_new_member_sync if GitHub.ldap_sync_enabled?

          user
        end
      end

      # Create the user's profile in the database.
      # It uses the user information retrieved from the ldap server.
      #
      # user: is the created User object.
      # user_info: is a hash with the information pulled from the ldap server.
      def create_profile(user, user_info)
        complete_name = profile_info(user_info, :name)

        if !complete_name.empty?
          user.create_profile(name: complete_name.first)
        end
      end

      # Create additional emails in the system
      #
      # user: is the created User object.
      # email_info: is an array with additional emails from the ldap server.
      #
      # Returns nothing.
      def create_emails(user, emails_info)
        emails_info.each do |email|
          user.add_email(email)
        end

        user.set_initial_gravatar_email
      end

      # Register the public ssh keys into github.
      # It uses the user information retrieved from the ldap server.
      #
      # user: is the created User object.
      # user_info: is a hash with the information pulled from the ldap server.
      #
      # Returns nothing.
      def create_public_keys(user, user_info)
        keys = profile_info(user_info, :key)
        return if !keys || keys.empty?
        GitHub::LDAP::UserSync.sync_public_keys(user, keys)
      rescue GitHub::LDAP::UserSync::InvalidPublicKeyError => error
        Failbot.report! error, error.payload
      end

      # Register the GPG keys into github.
      # It uses the user information retrieved from the ldap server.
      #
      # user: is the created User object.
      # user_info: is a hash with the information pulled from the ldap server.
      #
      # Returns nothing.
      def create_gpg_keys(user, user_info)
        keys = profile_info(user_info, :gpgkey)
        return if !keys || keys.empty?

        GitHub::LDAP::UserSync.sync_gpg_keys(user, keys)
      end

      # Generate an Array of groups that we'll use to authenticate the user with.
      # Since the group list comes from an environment variable we need to split it.
      #
      # Returns an Array with the configured groups.
      def authentication_groups
        GitHub.ldap_auth_groups
      end

      # Internal: Look up authentication groups in LDAP. Gives us the full DN.
      #
      # Returns an Array of Net::LDAP::Entry objects.
      def authentication_group_entries
        @authentication_group_entries ||= begin
          groups = []

          ldap_domains.each_value do |domain|
            groups.concat domain.groups(authentication_groups)
          end

          groups
        end
      end

      # Internal: Returns the Net::LDAP::Entry admin group, or nil if it is not
      # found or not configured.
      def ldap_admin_group
        return unless GitHub.ldap_admin_group

        GitHub::LDAP.search.groups(GitHub.ldap_admin_group).first
      end

      # Internal: Check if the LDAP entry is a member of the administrator group.
      #
      # entry: the Net::LDAP::Entry user object to validate membership of.
      #
      # Returns true if the entry is a member of the configured admin group, if
      # one is defined. Otherwise, returns true if this is the "first run" and
      # no other site admins exist.
      def is_admin?(entry)
        if ldap_admin_group
          admin_membership_validator.perform(entry)
        else
          GitHub.enterprise_first_run?
        end
      end

      # Internal: Reconcile a User's admin privileges.
      #
      # NOTE: Calls out to UserSync to manage this, which calls is_admin? above.
      def reconcile_admin(user, entry)
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub::LDAP::UserSync.new.reconcile_admin(user, entry)
        end
      end

      # Internal: Reconcile the User's fallback LDAP UID value.
      def reconcile_fallback_uid(user, entry)
        uid = profile_info(entry, :uid).first
        return if user.ldap_mapping.fallback_uid == uid
        ActiveRecord::Base.connected_to(role: :writing) do
          user.ldap_mapping.update_column :fallback_uid, uid
        end
      end

      # Generate a Hash of ldap base domains to perform user validations.
      #
      # Returns a Hash where the base name is the key and the GitHub::Ldap::Domain is the value.
      def ldap_domains
        return @ldap_domains if @ldap_domains

        domains = GitHub.ldap_base
        @ldap_domains = domains.each_with_object({}) do |domain, hash|
          hash[domain] = strategy.domain(domain)
        end
      end

      # Initialize the Ldap connection strategy.
      #
      # Returns a GitHub::Ldap object
      def strategy
        @strategy ||= begin
          options = configuration.merge \
            instrumentation_service: instrumentation_service
          GitHub::Ldap.new(options)
        end
      end

      # Internal: The membership validator to use when restricted groups are defined.
      def membership_validator
        @membership_validator ||=
          strategy.membership_validator.new strategy,
            authentication_group_entries,
            depth: GitHub.ldap_search_strategy_depth
      end
      attr_writer :membership_validator

      # Internal: The strategy to use to validate membership of the
      # administrative group.
      def admin_membership_validator
        @admin_membership_validator ||=
          strategy.membership_validator.new strategy,
            [ldap_admin_group],
            depth: GitHub.ldap_search_strategy_depth
      end
      attr_writer :admin_membership_validator

      # Internal: Retrieves attribute values using the reference attribute
      # names (uid, mail, etc), mapped to the configured attribute names
      # (sAMAccountNAme, mail, etc).
      #
      # - entry: Net::LDAP::Entry object
      # - field: the Symbol field, mapped to the configured attribute name
      #
      # Example:
      #
      #   entry["sAMAccountName"]   #=> "mtodd"
      #   profile_info(entry, :uid) #=> "mtodd"
      #
      # Returns an Array of attribute values for that field.
      def profile_info(entry, field)
        Array(entry[ldap_profile[field.to_s].to_sym])
      end

      # Public: Whether an LDAP entry has access in the directory
      #
      # entry: the Net::LDAP::Entry object being checked for access
      #
      # Access control checks are done the following order:
      # * ActiveDirectory userAccountControl (if available)
      # * membership of configured restricted access groups (if set)
      #
      # Returns an instance of GitHub::LDAP::Authorization
      def ldap_authorization(entry)
        state = :valid

        if control = user_account_control(entry)
          if user_account_control_authorized?(control)
            state = :valid_user_account_control
          else
            # exit early to avoid expensive membership validation if we already
            # know user is unauthorized.
            return GitHub::LDAP::Authorization.new(:invalid_user_account_control)
          end
        end

        if validate_membership?
          if valid_membership?(entry)
            state = :valid_membership
          else
            return GitHub::LDAP::Authorization.new(:invalid_membership)
          end
        end

        GitHub::LDAP::Authorization.new(state)
      end

      # Internal: userAccountControl value for given LDAP `entry`
      #
      # Returns a numeric String if available, nil otherwise.
      def user_account_control(entry)
        account_control = Array(entry[ACCOUNT_CONTROL_ATTR]).first
        if !account_control.nil? && account_control.to_s =~ /^\d+$/
          account_control.to_i
        end
      end

      # Internal: Whether userAccountControl flag is authorized in LDAP
      #
      # `user_account_control` - Numeric flag to check
      #
      # Returns true if flag is authorized, false otherwise.
      def user_account_control_authorized?(user_account_control)
        (user_account_control & ACCOUNT_DISABLED) != ACCOUNT_DISABLED
      end

      # Search an ldap mapping for a given login.
      #
      # login: is the user login.
      #
      # Returns nil if the login is not in the database.
      # Returns nil if there is no ldap mapping for that user.
      # Returns the ldap info if ldap mapping exists.
      def find_ldap_mapping_by_login(login)
        user = User.reify(login)
        return unless user
        return unless user.ldap_mapping

        strategy.domain(user.ldap_mapping.dn).bind
      end

      def with_ldap_domains
        message = INVALID_CREDENTIALS_MESSAGE

        ldap_domains.each do |base_name, domain|
          yield(base_name, domain)
        end

        [nil, message]
      end

      # Internal: Check if a user already has this LDAP DN assigned.
      #
      # dn: is the entry dn associated with a new user.
      #
      # Returns true if we already have the DN associated with a user.
      def ldap_mapping_present?(dn)
        if collision = LdapMapping.by_dn(dn).where(subject_type: "User").first
          GitHub::Authentication.logger.info("DN already assigned", "code.namespace" => self.class.name, "code.function" => __method__, "ldap.dn" => dn, "gh.auth.login" => collision.login)
          true
        end
      end

      # Whether or not this authentication strategy allows built-in autentication
      # as a fallback (e.g. Allow users to sign in via SAML or username/password).
      def builtin_auth_fallback?
        GitHub.builtin_auth_fallback
      end
    end

    class LDAPSync
      include GitHub::Telemetry::Logs::Loggable
    end
  end
end
