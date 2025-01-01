# typed: true
# frozen_string_literal: true

class CompromisedPasswordDatasource < ApplicationRecord::Collab
  scope :not_qintel, -> { where.not(name: "qintel") }

  validates :name,    presence: true
  validates :version, presence: true, uniqueness: { scope: :name, case_sensitive: false }

  LOAD_BATCH_SIZE = 100
  READ_BATCH_SIZE = 1000
  MAX_QUERY_ATTEMPTS = 5

  # Create a new datasource and load its credentials.
  #
  # name:           - The String name of the datasource.
  # version:        - The String version of the datasource.
  # sha1_passwords: - An Enumerator of String hex SHA1 password hashes.
  #
  # Returns the new CompromisedPasswordDatasource instance.
  def self.store_passwords(name:, version:, sha1_passwords:)
    datasource = retry_on_find_or_create_error do
      where(name: name, version: version).first || create!(name: name, version: version)
    end

    GitHub.dogstats.distribution_time("qintel.store_passwords.dist.duration", tags: ["version:#{version}", "datasource:#{name}"]) do
      sha1_passwords.each_slice(LOAD_BATCH_SIZE) do |batch|
        return if GitHub.flipper[:disable_qintel_imports].enabled?

        write_passwords(batch)
        stat_credentials_loaded(name, version, batch.count)
      end
    end
    datasource
  end

  def self.write_passwords(batch)
    # First check for passwords we've previously imported
    # We can check this on a replica. In the event that this was _just_
    # inserted by another process, that can be handled by INSERT IGNORE.
    existing_shas =
      ActiveRecord::Base.connected_to(role: :reading) do
        CompromisedPassword.where(sha1_password: batch).pluck(:sha1_password)
      end

    # Determine which SHAs of this batch are missing from the DB
    new_shas = batch - existing_shas

    # If the entire batch already exists, we're done!
    return if new_shas.empty?

    # Otherwise we'll need to make some INSERTs.
    # Check that replication lag is healthy

    # Here we loop over the SHAs instead of bulk-inserting, which should
    # avoid potential deadlocks when we are importing from multiple sources
    # in parallel.

    if GitHub.flipper[:qintel_throttle_per_write].enabled?
      new_shas.each do |sha|
        throttle_with_retry(max_retry_count: MAX_QUERY_ATTEMPTS, low_priority: true) do
          CompromisedPasswordDatasource.connection.insert(Arel.sql(<<~SQL, sha: sha))
            INSERT IGNORE INTO compromised_passwords (sha1_password)
            VALUES (:sha)
          SQL
        end
      end
    else
      throttle_with_retry(max_retry_count: MAX_QUERY_ATTEMPTS, low_priority: true) do
        new_shas.each do |sha|
          CompromisedPasswordDatasource.connection.insert(Arel.sql(<<~SQL, sha: sha))
            INSERT IGNORE INTO compromised_passwords (sha1_password)
            VALUES (:sha)
          SQL
        end
      end
    end
  end

  # Create a new datasource and load its credentials.
  #
  # compromised_records: - An Enumerator of arrays ["username", "password"]
  #
  # Returns the new CompromisedPasswordDatasource instance.
  def self.check_for_compromise(compromised_records:, name:, version:)
    CompromisedPasswordDatasource.throttle_with_retry(max_retry_count: 8, low_priority: true) do
      GitHub.dogstats.distribution_time("qintel.check_for_compromise.dist.duration", tags: ["version:#{version}", "datasource:#{name}"]) do
        compromised_records.each_slice(READ_BATCH_SIZE) do |batch|
          input_count = batch.count
          batch = batch.filter { |u, p| valid_login_or_email?(u) && valid_password?(p) }

          # Stat _after_ we've filtered the batch so we can present the accurate count of the accepted credentials
          stat_credentials_processed(name, version, batch.count)
          stat_credentials_dropped(name, version, input_count - batch.count)

          logins = []
          emails = []

          batch.each do |username, _password|
            if username.include?("@")
              emails << username.downcase
            else
              logins << username.downcase
            end
          end

          valid_emails = User.select("users.*, user_emails.email as user_email").
            joins(:emails).
            where(user_emails: { email: emails })

          valid_logins = User.select("users.*, NULL as user_email").
            where(login: logins)

          valid_users = User.find_by_sql("SELECT * FROM (#{valid_emails.to_sql} UNION #{valid_logins.to_sql}) AS users")

          valid_users.each do |user|
            stat_email_match(name, version, user)
            next if user.password_check_metadata.exact_match?
            batch.select do |username, _password|
              username.downcase == user.login&.downcase || username.downcase == user.user_email&.downcase
            end.each do |_, password|
              if user.authenticated_by_password?(password)
                stat_exact_match(name, version, user)
                user.mark_compromised_via_direct_match(password: password, name: name, version: version)
                AccountMailer.username_and_password_compromised(user).deliver_later
                break
              end
            end
          end
        end
      end
    end
  end

  # Sets the time that the import of compromised
  # records finished at
  def mark_import_as_finished!
    self.update!(import_finished_at: Time.now)
    GitHub.dogstats.increment("auth.compromised_password.import_finished", tags: [
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  def self.stat_exact_match(name, version, user)
    GitHub.dogstats.increment("auth.compromised_password.exact_match", tags:  [
      "employee:#{user&.employee?}",
      "spammy:#{user&.spammy?}",
      "tfa_enabled:#{user&.two_factor_authentication_enabled?}",
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  def self.stat_email_match(name, version, user)
    GitHub.dogstats.increment("auth.compromised_password.email_match", tags: [
      "employee:#{user&.employee?}",
      "spammy:#{user&.spammy?}",
      "tfa_enabled:#{user&.two_factor_authentication_enabled?}",
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  def self.stat_credentials_loaded(name, version, count)
    GitHub.dogstats.count("auth.compromised_password.credentials_loaded", count, tags: [
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  def self.stat_credentials_processed(name, version, count)
    GitHub.dogstats.count("auth.compromised_password.credentials_processed", count, tags: [
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  def self.stat_credentials_dropped(name, version, count)
    GitHub.dogstats.count("auth.compromised_password.credentials_dropped", count, tags: [
      "version:#{version}",
      "datasource:#{name}",
    ])
  end

  private_class_method def self.valid_login_or_email?(str)
    # Checks if the provided string matches the MySQL utf8mb3 encoding
    # This is the collation used in our database for string columns.
    #
    # In MySQL 8.0, the utf8mb3 character set is considered deprecated in favor of utf8mb4, which allows 4-byte characters.
    # In future MySQL versions, the default UTF-8 character set may be changed to utf8mb4.
    # However, we never expect a 4-byte character to be valid in a username or email, so it's fine to be overly restrictive here.
    !str.blank? && str.valid_encoding? && str.encoding.name == "UTF-8" && str.chars.all? { |c| c.bytes.count <= 3 }
  end

  private_class_method def self.valid_password?(str)
    return false if str.blank?
    invalid_patterns = [
      "\u0000", # null bytes
    ]
    !(str.respond_to?(:match) && str.match?(Regexp.union(invalid_patterns)))
  end
end
