# typed: true
# frozen_string_literal: true

class EnterpriseInstallationUserAccountsImporter
  attr_reader :business, :installation, :upload_id, :actor

  # Raised when upload data uses now unsupported GPG encryption.
  # This should only happen with files exported and encrypted on GHES 2.18 installations.
  class UnsupportedEncryptionError < StandardError
  end

  # Raised when the upload data is not a user account export.
  class InvalidDataError < StandardError
  end

  # Create a new EnterpriseInstallationUserAccountsImporter in preparation for
  # importing and syncing a user accounts upload.
  #
  # business - The Business that owns the Enterprise Server installation.
  # installation - An optional existing EnterpriseInstallation for the sync.
  # upload_id - An Integer representing the ID of an
  # EnterpriseInstallationUserAccountsUpload pointing to a file containing the
  # data to be synced.
  # actor - The User performing the sync.
  def initialize(business:, installation: nil, upload_id:, actor:)
    @business = business
    @installation = installation
    @upload_id = upload_id
    @actor = actor
  end

  # Public: Parses a JSON String of user accounts data sourced from an
  # Enterprise Server installation into a Hash ready to be synchronized.
  #
  # accounts_data - A JSON string representing the user accounts data sourced
  # from an Enterprise Server installation.
  #
  # Returns as Hash.
  def self.parse_user_accounts_data(accounts_data)
    raise ArgumentError, "accounts_data cannot be nil" if accounts_data.nil?

    begin
      result = JSON.parse accounts_data, symbolize_names: true
      raise InvalidDataError, "accounts_data is not in a valid format" if result[:instance].blank? || result[:version].blank?
      if result[:users].instance_of?(String) && result[:instance] && server_id = result[:instance][:server_id]
        result[:users] = decrypt_data(result.delete(:users))
      end
      result
    rescue JSON::ParserError
      raise ArgumentError, "accounts_data is not valid JSON"
    end
  end

  # Private: Helper method used by parse_user_accounts_data to decrypt encrypted
  # data.
  def self.decrypt_data(data)
    raise UnsupportedEncryptionError.new("User account data in upload was encrypted using GPG encryption which is now unsupported.") if data.starts_with?("-----BEGIN PGP MESSAGE-----\n")
    JSON.parse(GitHub::Connect::Authenticator.new.decrypt_message(data).to_s, symbolize_names: true)
  end

  # Public: Synchronize an upload of user accounts for an Enterprise Server
  # installation with the given business and installation when provided.
  #
  # Called from SyncEnterpriseServerUserAccountsJob to process an import.
  #
  # The uploaded file must be sourced from an Enterprise Server installation
  # and is expected to be in this format:
  #
  # {
  #   "version": 1,
  #   "instance": {
  #     "license": "owHsuVmu9EyaHlaydJWGrnR...",
  #     "host_name": "github.localhost",
  #     "http_only": true,
  #     "version": "unknown",
  #     "public_key": "key"
  #   },
  #   "users": [
  #     {
  #       "user_id": 12345,
  #       "created_at": "2019-03-11 21:19:53 +0000",
  #       "login": "octocat",
  #       "profile_name": "The Octocat",
  #       "site_admin": true,
  #       "using_advanced_security": false,
  #       "emails": [
  #         {
  #           "email": "octocat@github.com",
  #           "primary": true
  #         },
  #         {
  #           "email": "another@example.com"
  #         }
  #       ]
  #     }
  #   ]
  # }
  #
  # Returns nothing.
  def synchronize_user_accounts_data!
    raise RuntimeError, "business cannot be nil" if @business.nil?
    raise RuntimeError, "upload_id cannot be nil" if @upload_id.nil?
    raise RuntimeError, "actor cannot be nil" if @actor.nil?

    Failbot.push(business_id: @business.id)
    @upload = EnterpriseInstallationUserAccountsUpload.find_by \
      id: @upload_id,
      business_id: @business.id

    unless @upload
      raise RuntimeError, "no upload found with ID `#{@upload_id}` belonging to business with ID `#{@business.id}`"
    end

    @accounts_data = @upload.download_and_read_file(actor: @actor)
    begin
      @accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
    rescue ArgumentError => error
      report_failure error
      return
    rescue InvalidDataError => error
      report_failure error
      return
    end

    @installation ||= find_existing_or_create_installation
    @upload.update enterprise_installation: @installation

    # Cache all users and business accounts for the emails in @accounts_hash
    # We preload the caches outside of the transaction as this can be quite slow on large files
    # which unnecessarily blocks the transaction
    build_email_to_user_account_caches

    begin
      ApplicationRecord::Collab.transaction do
        # Delete any existing accounts for the installation that don't exist
        # in @accounts_hash.
        delete_missing_accounts

        # Bulk import the user accounts.
        user_accounts_affected_rows = import_user_accounts

        # Bulk import the emails.
        emails_affected_rows = import_emails

        # Bulk remove missing emails
        delete_missing_emails_affected_rows = delete_missing_emails

        # Delete any business user accounts that are no longer associated to any
        # server or cloud user accounts.  This bypasses any destroy hooks and runs
        # the delete as a single operation
        @business.user_accounts.orphaned.delete_all
      end

      GitHub.dogstats.histogram \
        "enterprise_installation_user_accounts.import.upload_size",
        @upload.size
      GitHub.dogstats.histogram \
        "enterprise_installation_user_accounts.import.accounts_imported",
        @accounts_hash[:users].size

      @upload.sync_success!

      GlobalInstrumenter.instrument "licensing.enterprise_installation_synced", {
        business: @business,
        enterprise_installation: @installation,
      }

      @business.instrument_import_license_usage \
        actor: @actor,
        enterprise_installation: @installation
      @business.update_license_usage
    rescue GitHub::SQL::BadBind, ActiveRecord::ActiveRecordError => error
      report_failure error
      return
    end

    BusinessMailer.sync_user_accounts(@actor, true, @upload).deliver_later
  end

  private

  # 1. Try to find an installation belonging to the business that matches the
  #    provided server_id.
  # 2. Otherwise, create a new installation for the upload.
  def find_existing_or_create_installation
    server_id = @accounts_hash[:instance][:server_id].presence
    if server_id && installation = @business.enterprise_installations.find_by(server_id: server_id)
      return installation
    end

    # Attempt to load the license from @accounts_hash[:instance][:license] and
    # read any data required for creating an EnterpriseInstallation.
    if license = load_license
      customer_name = license.company
      license_public_key = Base64.decode64(license.customer_public_key)
    else
      customer_name = @business.name
      license_public_key = ""
    end

    EnterpriseInstallation.create! \
      owner: @business,
      server_id: @accounts_hash[:instance][:server_id],
      host_name: @accounts_hash[:instance][:host_name],
      customer_name: customer_name,
      license_hash: Digest::SHA256.base64digest(@accounts_hash[:instance][:license]),
      http_only: @accounts_hash[:instance][:http_only],
      version: @accounts_hash[:instance][:version],
      license_public_key: license_public_key
  end

  def load_license
    # An authenticator also acts as a "license reader"
    authenticator = GitHub::Connect::Authenticator.new
    authenticator.load_license(Base64.decode64(@accounts_hash[:instance][:license]))
  end

  def delete_missing_accounts
    slice_size = 100
    remote_user_ids = @accounts_hash[:users].map { |account| account[:user_id] }
    account_ids = @installation.user_accounts.
      where.not(remote_user_id: remote_user_ids).pluck(:id)
    return if account_ids.empty?

    EnterpriseInstallationUserAccount.throttle do
      account_ids.each_slice(slice_size) do |slice|
        EnterpriseInstallationUserAccount.connection.delete(Arel.sql(<<-SQL, account_ids: slice))
          DELETE FROM enterprise_installation_user_accounts
          WHERE id in (:account_ids)
        SQL

        EnterpriseInstallationUserAccountEmail.connection.delete(Arel.sql(<<-SQL, account_ids: slice))
          DELETE FROM enterprise_installation_user_account_emails
          WHERE enterprise_installation_user_account_id IN (:account_ids)
        SQL
      end
    end
  end

  # Sets two instance variables @dotcom_users_by_email and @enterprise_users_by_email
  # Each contains a hash that maps from email address to an existing
  # BusinessUserAccount
  def build_email_to_user_account_caches
    ActiveRecord::Base.connected_to(role: :reading) do
      emails = @accounts_hash[:users].flat_map { |u| u[:emails] }
                                    .select { |e| e[:primary] }
                                    .map { |e| e[:email] }

      @dotcom_users_by_email =
        # Business with SAML SSO
        if @business.saml_sso_enabled? || @business.oidc_enabled? || @business.organizations.any?(&:saml_sso_enabled?)
          @business.dotcom_users_from_extid_emails(emails)
        # EMU business
        elsif @business.enterprise_managed_user_enabled?
          users = T.let([], T::Array[::User])
          user_accounts = {}
          emails.each_slice(1000) do |slice|
            tmp_users = T.unsafe(User.includes(:profile)).find_by_emails(slice, business: @business).values
            users += tmp_users
            user_ids = tmp_users.map(&:id)
            @business.user_accounts.where(user_id: user_ids).map do |account|
              user_accounts[account.user_id] = account
            end
          end
          users.map { |u| [T.must(T.must(u.profile).email).downcase, user_accounts[u.id]] }.to_h
        end || {}
      # Standard login Business
      # We also include the users with matching user-provided email addresses for SAML Businesses to increase the
      # chance of finding a match. This isn't needed for EMUs because the user can't add additional emails to their accounts.
      @dotcom_users_by_email.merge! @business.dotcom_users_from_emails(emails) unless @business.enterprise_managed_user_enabled?

      @enterprise_users_by_email = @business.enterprise_users_from_emails(emails)
    end
  end

  # Finds cached BusinessUserAccount for email
  def find_cached_user_account(email)
    @dotcom_users_by_email[email.downcase] || @enterprise_users_by_email[email.downcase]
  end

  # Returns an existing BusinessUserAccount for each of the email addresses
  # or creates a new one if none exists. Also updates the login if the primary
  # email address has changed for a GHES-only user.
  def find_existing_or_create_user_account(user)
    email = user[:emails].find { |e| e[:primary] }
    if email
      account = find_cached_user_account(email[:email])
      if account
        if account[:user_id].nil? && account[:login] != email[:email]
          primary_emails = Set.new
          account.enterprise_installation_user_accounts.each { |a| primary_emails << a.emails.primary.pluck(:email).first }
          # Don't make change if there are multiple primary emails that don't match
          return account if primary_emails.size > 1

          account[:login] = email[:email]
          account.save!
        end
        return account
      end
    end

    email = user[:emails].first if !email
    login = email ? email[:email] : user[:login] || "user-#{user[:user_id]}"
    business.user_accounts.create(login: login)
  end

  def import_user_accounts
    slice_size = 100
    rows = 0
    @accounts_hash[:users].each_slice(slice_size) do |slice|
      accounts_sql = Arel.sql(<<-SQL)
        INSERT INTO enterprise_installation_user_accounts (
          `enterprise_installation_id`,
          `remote_user_id`,
          `remote_created_at`,
          `login`,
          `profile_name`,
          `site_admin`,
          `business_user_account_id`,
          `using_advanced_security`,
          `created_at`,
          `updated_at`
        ) VALUES
      SQL

      slice.each_with_index do |user, index|
        last = (slice.length - 1) == index
        user_account = find_existing_or_create_user_account(user)

        # true, false and not providing the key are all fine, but if the key is present
        # and the value is null then there was an error fetching the user's advanced security status
        # and we need to investigate
        if user.has_key?(:using_advanced_security) && user[:using_advanced_security].nil?
          GitHub.dogstats.increment("enterprise_installation_user-accounts_importer.missing_advanced_security")
          GitHub.logger.error(
            "exception.message": "Could not detect advanced security usage",
            "code.namespace": "EnterpriseInstallationUserAccountsImporter",
            "code.function": "import_user_accounts",
            "gh.installation.id": @installation.id,
            "gh.user.id": user_account.id,
          )
        end

        values = {
            enterprise_installation_id: @installation.id,
            remote_user_id: user[:user_id],
            remote_created_at: user[:created_at]&.first(19),
            login: user[:login] || user_account.login,
            profile_name: user[:profile_name],
            site_admin: user[:site_admin] || false,
            business_user_account_id: user_account.id,
            using_advanced_security: user[:using_advanced_security],
          }
        accounts_sql += Arel.sql(<<-SQL, **values)
          (
            :enterprise_installation_id,
            :remote_user_id,
            #{user[:created_at].nil? ? "NOW()" : ":remote_created_at"},
            :login,
            :profile_name,
            :site_admin,
            :business_user_account_id,
            :using_advanced_security,
            NOW(),
            NOW()
          )#{"," unless last}
        SQL
      end

      accounts_sql += Arel.sql(<<-SQL)
        ON DUPLICATE KEY UPDATE
          `remote_created_at` = VALUES(`remote_created_at`),
          `login` = VALUES(`login`),
          `profile_name` = VALUES(`profile_name`),
          `site_admin` = VALUES(`site_admin`),
          `business_user_account_id` = VALUES(`business_user_account_id`),
          `using_advanced_security` = VALUES(`using_advanced_security`),
          `updated_at` = NOW()
      SQL

      affected_rows = ApplicationRecord::Collab.throttle { EnterpriseInstallationUserAccount.connection.update(accounts_sql) }
      rows += affected_rows
    end
    rows
  end

  def import_emails
    slice_size = 100
    rows = 0
    @accounts_hash[:users].each_slice(slice_size) do |slice|
      emails_sql = Arel.sql(<<-SQL)
        INSERT INTO enterprise_installation_user_account_emails (
          `enterprise_installation_user_account_id`,
          `email`,
          `primary`,
          `created_at`,
          `updated_at`
        ) VALUES
      SQL

      emails = []
      slice.each do |user|
        user[:emails].each do |email|
          primary = email.has_key?(:primary) ? email[:primary] : false
          emails << {
            enterprise_installation_user_account_id: remote_user_id_to_account_id[user[:user_id]],
            email: email[:email],
            primary: primary,
          }
        end
      end

      emails.each_with_index do |email, index|
        last = (emails.length - 1) == index
        values = {
          enterprise_installation_user_account_id: email[:enterprise_installation_user_account_id],
          email: email[:email],
          primary: email[:primary],
        }
        emails_sql += Arel.sql(<<-SQL, **values)
          (
            :enterprise_installation_user_account_id,
            :email,
            :primary,
            NOW(),
            NOW()
          )#{"," unless last}
        SQL
      end

      next if emails.blank?

      emails_sql += Arel.sql(<<-SQL)
        ON DUPLICATE KEY UPDATE
          `primary` = VALUES(`primary`),
          `updated_at` = NOW()
      SQL

      affected_rows = EnterpriseInstallationUserAccountEmail.throttle { EnterpriseInstallationUserAccountEmail.connection.update(emails_sql) }
      rows += affected_rows
    end
    rows
  end

  # Removes all emails that are associated with an enterprise installation, but aren't included
  # in the uploaded JSON.
  def delete_missing_emails
    slice_size = 100
    rows = 0
    emails = Set.new
    account_ids = Set.new
    @accounts_hash[:users].map do |user|
      user[:emails].each { |email| emails << email[:email] }
      account_ids << remote_user_id_to_account_id[user[:user_id]]
    end

    return if emails.blank? || account_ids.blank?

    account_ids.each_slice(slice_size) do |slice|
      delete_emails_sql = Arel.sql(<<-SQL, emails: emails.to_a, account_ids: slice)
        DELETE FROM enterprise_installation_user_account_emails
        WHERE `enterprise_installation_user_account_id` IN (:account_ids)
        AND `email` NOT IN (:emails)
      SQL

      affected_rows = EnterpriseInstallationUserAccountEmail.throttle { EnterpriseInstallationUserAccountEmail.connection.delete(delete_emails_sql) }
      rows += affected_rows
    end
    rows
  end

  # Map the account ids just inserted/updated to remote_user_ids so we
  # can bulk import and delete emails.
  def remote_user_id_to_account_id
    @_remote_user_id_to_account_id ||= @installation.user_accounts.pluck(:remote_user_id, :id).to_h
  end

  def report_failure(error)
    # Update the sync state
    @upload.sync_failure!

    Failbot.report(error, app: "github")
    GitHub.dogstats.increment("enterprise_installation_user_accounts.import.error")

    # Update the job status
    job_status = SyncEnterpriseServerUserAccountsJob.status(@business, @upload.id)
    job_status.error! if job_status

    BusinessMailer.sync_user_accounts(@actor, false, @upload).deliver_later
  end
end
