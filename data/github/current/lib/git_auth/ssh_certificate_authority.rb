# typed: true
# frozen_string_literal: true

module GitAuth
  class SSHCertificateAuthority
    DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS = 8784 # 366 days

    # We support any type of cert other than DSA.
    SUPPORTED_CERT_ALGOS = [
      SSHData::Certificate::ALGO_RSA,
      SSHData::Certificate::ALGO_ECDSA256,
      SSHData::Certificate::ALGO_ECDSA384,
      SSHData::Certificate::ALGO_ECDSA521,
      SSHData::Certificate::ALGO_ED25519,
      SSHData::Certificate::ALGO_SKECDSA256,
      SSHData::Certificate::ALGO_SKED25519,
    ]

    # Critical options that we know how to handle. Others result in an error.
    SUPPORTED_CRITICAL_OPTIONS = [
      SSHData::Certificate::CRITICAL_OPTION_SOURCE_ADDRESS,
    ]

    # Validate an SSH certificate. This involves checking a bunch of fields on the
    # cert, verifying its signature, and looking up the corresponding CA and user.
    #
    # certificate - A String SSH certificate in OpenSSH format.
    # max_lifetime_checks - If true, apply max lifetime checks using the valid_after and valid_before dates and the corresponding max_ssh_cert_lifetime_hours value on the CA.
    #                       This is a conditional at the function level so that this check is only applied to the callsite that can provide the error response to the SSH client.
    #
    # Returns an Array. The first element is a Symbol describing the result of
    # validation. The second element is the user ID associated with the cert. The third the user login associated with the cert.
    # The fourth the user display login associated with the cert. The fifth is the SshCertificateAuthority that issued the cert.
    def self.validate_certificate(certificate, ip: "none", max_lifetime_checks: false)
      # Parse the certificate. This also verifies the cert's signature.
      parsed = begin
                 SSHData::Certificate.parse_openssh(certificate)
               rescue SSHData::Error
                 return [:parse_error, nil, nil, nil, nil]
               end

      if parsed.type != SSHData::Certificate::TYPE_USER
        # Certs can be issued for hosts or users. We want user certs
        return [:host_cert, nil, nil, nil, nil]
      elsif SUPPORTED_CERT_ALGOS.exclude?(parsed.algo)
        # We don't support DSA keys
        return [:unsupported_algo, nil, nil, nil, nil]
      elsif GitHub::SSH.blocklisted_key?(parsed.public_key)
        return [:blacklisted, nil, nil, nil, nil]
      elsif weak_rsa_key?(parsed.public_key)
        return [:weak_rsa, nil, nil, nil, nil]
      elsif Time.now < parsed.valid_after
        # Cert isn't valid yet
        return [:too_early, nil, nil, nil, nil]
      elsif Time.now > parsed.valid_before
        # Cert is expired
        return [:too_late,  nil, nil, nil, nil]
      elsif !parsed.allowed_source_address?(ip)
        # The certificate allowlists IP addresses. This one isn't included.
        return [:bad_ip, nil, nil, nil, nil]
      elsif (parsed.critical_options.keys - SUPPORTED_CRITICAL_OPTIONS).any?
        # The certificate includes critical options that we don't support
        return [:critical_opts, nil, nil, nil, nil]
      end

      response, ca = get_ca(parsed)
      if response != :ok
        return [response, nil, nil, nil, nil]
      end

      valid_before = parsed.valid_before
      valid_after = parsed.valid_after
      validity_delta = valid_before - valid_after
      valid_before_is_undefined = valid_before == SSHData::Certificate::END_OF_TIME
      valid_after_is_undefined = valid_after == SSHData::Certificate::BEGINNING_OF_TIME
      payload = {
        "gh.gitauth.ssh_cert.valid_after" => valid_after,
        "gh.gitauth.ssh_cert.valid_before" => valid_before,
        "gh.gitauth.ssh_cert.validity_duration" => validity_delta,
        "gh.gitauth.ssh_cert.valid_before_is_undefined" => valid_before_is_undefined,
        "gh.gitauth.ssh_cert.valid_after_is_undefined" => valid_after_is_undefined,
      }
      ::GitHub.logger.info("SSH certificate validity data", payload)
      GitHub.dogstats.increment("ssh_certificate_authority.validity_data", tags: [
        "validity_less_than_1_day:#{validity_delta < 1.day}",
        "validity_less_than_1_week:#{validity_delta < 1.week}",
        "validity_less_than_1_month:#{validity_delta < 1.month}",
        "validity_less_than_1_year:#{validity_delta < 1.year}",
        "validity_less_than_2_years:#{validity_delta < 2.years}",
        "validity_less_than_5_years:#{validity_delta < 5.years}",
        "validity_less_than_10_years:#{validity_delta < 10.years}",
        "validity_less_than_30_years:#{validity_delta < 30.years}",
        "valid_before_is_undefined:#{valid_before_is_undefined}",
        "valid_after_is_undefined:#{valid_after_is_undefined}",
      ])

      # for certificates that have a "max_ssh_cert_lifetime_hours" we need to check two things
      # 1. that the certificate has a max lifetime no longer than the defined value
      # 2. the corresponding user was created before the cert was created and hasn't had a username rename since the cert was created
      # by enforcing (1), we can be certain the cert has a proper "valid_after" date which can be used to enforce (2)
      #
      # these checks are used to prevent user rename issues that were discovered in the following bounty:
      # https://github.com/github/authentication/issues/906
      #
      # we don't apply these checks to CAs without a "max_ssh_cert_lifetime_hours" to provide backward compatibility
      # for old certs. New CAs are assigned a "max_ssh_cert_lifetime_hours" by default and cannot be opted out of.
      apply_validity_checks = max_lifetime_checks && ca.max_ssh_cert_lifetime_hours
      GitHub.dogstats.increment("ssh_certificate_authority.validity_checking", tags: ["applied:#{apply_validity_checks}"])

      # check (1) first, as an optimization to reject certs without a proper
      # max lifetime _before_ we even bother to lookup the associated account
      # we check (2) below
      if apply_validity_checks
        max_ssh_cert_lifetime_seconds = ca.max_ssh_cert_lifetime_hours * 3600
        if validity_delta > max_ssh_cert_lifetime_seconds || validity_delta < 0
          GitHub.dogstats.increment("ssh_certificate_authority.validity_check_rejection", tags: ["reason:invalid_validity_period"])
          return [:invalid_validity_period, nil, nil, nil, ca]
        end
      end

      result, user_info = get_user_info(parsed)
      ca.user_id = user_info[:id]
      has_id_extensions = has_id_extensions?(parsed)
      has_login_extensions = has_login_extensions?(parsed)
      GitHub.dogstats.increment("ssh_certificate_authority.extension_parsing", tags: [
        "result:#{result}",
        "has_id_extensions:#{has_id_extensions}",
        "has_login_extensions:#{has_login_extensions}",
      ])

      # if the user lookup was considered :ok
      # we can perform the second validity check mentioned above in (2)
      # check that the corresponding user was created before the certs "valid_after" date
      # _and_ that the user didn't have any renames after the certs "valid_after" date
      #
      # we know that the cert has a proper "valid_after" date since we would have already failed in check (1) above otherwise
      # we also only need to run this check if the result was :ok and the cert has a login extension (we don't care about user creation or renames for certs with id extensions)
      if result == :ok && has_login_extensions && apply_validity_checks
        user_created_after_cert = user_info[:created_at] > valid_after
        user_rename_occurred_after_cert = user_info[:renamed_at] && user_info[:renamed_at] > valid_after

        if user_created_after_cert || user_rename_occurred_after_cert
          GitHub.dogstats.increment("ssh_certificate_authority.validity_check_rejection", tags: ["reason:invalid_due_to_user_activity"])
          return [:invalid_due_to_user_activity, nil, nil, nil, ca]
        end
      end

      [result, user_info[:id], user_info[:login], user_info[:display_login], ca, {
        fingerprint_sha256: parsed.public_key.fingerprint,
        ca_fingerprint_sha256: parsed.ca_key.fingerprint,
        valid_before: "#{valid_before.to_i}",
        valid_after: "#{valid_after.to_i}",
        validate_user: has_login_extensions
      }]
    end

    def self.get_user_info(parsed_certificate)
      # don't accept the cert if it contains the legacy extension _and_ the new ID exension
      if has_id_extensions?(parsed_certificate) && has_login_extensions?(parsed_certificate)
        return [:conflicting_extensions, {}]
      end

      # if we can get the user by the new ID extension, use that and short circuit here
      # if there is an issue attempting the ID extension, fall back to the old behavior if the
      # CA is still eligible to use the login extension.
      response, user_info = get_user_info_by_id_extension(parsed_certificate)
      if response == :ok
        return [:ok, user_info]
      end

      response, user_info = get_user_info_by_login_extension(parsed_certificate)
      if response != :ok
        return [response, {}]
      end

      [:ok, user_info]
    end
    private_class_method :get_user_info

    def self.has_id_extensions?(parsed_certificate)
      parsed_certificate.extensions.values_at(*get_valid_id_extensions).compact.any?
    end
    private_class_method :has_id_extensions?

    def self.has_login_extensions?(parsed_certificate)
      parsed_certificate.extensions.values_at(*get_valid_login_extensions).compact.any?
    end
    private_class_method :has_login_extensions?

    def self.get_user_info_by_id_extension(parsed_certificate)
      id_exts = parsed_certificate.extensions.values_at(*get_valid_id_extensions).compact
      return [:no_id, nil] if id_exts.empty?

      # lookup users from extension values, preferring user from GHES-specific
      # extension, but always falling back to main github.com extension.
      query = Arel.sql(<<-SQL, ids: id_exts)
        SELECT id, login, display_login, created_at, raw_data
        FROM users
        WHERE id IN (:ids)
        AND type = 'User'
      SQL

      if GitHub.multi_tenant_enterprise?
        tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
        query += Arel.sql(<<-SQL, business_id: tenant_id)
          AND business_id=:business_id
        SQL
      end

      rows = ApplicationRecord::Domain::Users.connection.select_all(query).to_a

      rows_hash = rows.map do |row|
        renamed_at = nil
        if row["raw_data"]
          raw_data_deserialized = GitHub::ZSON.decode(row["raw_data"])
          renamed_at = raw_data_deserialized["renamed_at"]
        end
        [
          row["id"].to_s,
          {
            id: row["id"].to_s,
            login: row["login"],
            display_login: row["display_login"],
            created_at: row["created_at"],
            renamed_at: renamed_at
          }
        ]
      end.to_h
      user_info = T.let(nil, T.nilable([String, T::Hash[Symbol, T.untyped]]))
      id_exts.each do |id_ext|
        if (user_info = rows_hash[id_ext])
          break
        end
      end
      return [:no_user, nil] if user_info.nil?

      [:ok, user_info]
    end
    private_class_method :get_user_info_by_id_extension

    def self.get_user_info_by_login_extension(parsed_certificate)
      login_exts = parsed_certificate.extensions.values_at(*get_valid_login_extensions).compact
      return [:no_user, nil] if login_exts.empty?

      # lookup users from extension values, preferring user from GHES-specific
      # extension, but always falling back to main github.com extension.
      query = if GitHub.multi_tenant_enterprise?
        tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
        Arel.sql(<<-SQL, logins: login_exts, business_id: tenant_id)
          SELECT id, login, display_login, created_at, raw_data
          FROM users
          WHERE display_login IN (:logins)
          AND type = 'User'
          AND business_id=:business_id
        SQL
      else
        Arel.sql(<<-SQL, logins: login_exts)
          SELECT id, login, display_login, created_at, raw_data
          FROM users
          WHERE login IN (:logins)
          AND type = 'User'
        SQL
      end
      rows = ApplicationRecord::Domain::Users.connection.select_all(query).to_a

      rows_hash = rows.map do |row|
        renamed_at = nil
        if row["raw_data"]
          raw_data_deserialized = GitHub::ZSON.decode(row["raw_data"])
          renamed_at = raw_data_deserialized["renamed_at"]
        end

        [
          GitHub.multi_tenant_enterprise? ? row["display_login"] : row["login"],
          {
            id: row["id"].to_s,
            login: row["login"],
            display_login: row["display_login"],
            created_at: row["created_at"],
            renamed_at: renamed_at
          }
        ]
      end.to_h
      user_info = T.let(nil, T.nilable([String, T::Hash[Symbol, T.untyped]]))
      login_exts.each do |login_ext|
        if (user_info = rows_hash[login_ext])
          break
        end
      end
      return [:no_user, nil] if user_info.nil?

      [:ok, user_info]
    end
    private_class_method :get_user_info_by_login_extension

    def self.get_ca(parsed_certificate)
      fingerprint = parsed_certificate.ca_key.fingerprint
      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
        fingerprint = fingerprint << "_#{current_tenant.shortcode}"
      end

      ca_fpr = Base64.decode64(fingerprint)
      ca = SshCertificateAuthority.where(fingerprint: ca_fpr).first
      ca = with_model_object(ca)

      return [:no_ca, nil] if ca.nil?
      return [:bad_plan, nil] unless ca.owner_is_eligible_for_feature?

      [:ok, ca]
    end
    private_class_method :get_ca

    # Is the given RSA key too weak to be used?
    #
    # parsed - An SSHData::PublicKey::Base subclass instance.
    #
    # Returns boolean.
    def self.weak_rsa_key?(parsed)
      return false unless parsed.algo == SSHData::PublicKey::ALGO_RSA
      parsed.openssl.params["n"].num_bits < 2048 || GitHub::SSH.weak_rsa_key?(parsed.openssl)
    end
    private_class_method :weak_rsa_key?

    def self.with_model_object(ca)
      return unless ca

      if ca.owner.nil?
        GitHub.dogstats.increment("ssh_certificate_authority.check_owner_failure")
        ::GitHub.logger.info("SSH certificate authority has no owner", {
          "gh.gitauth.ssh_cert.id": ca.id,
          "gh.gitauth.ssh_cert.owner_type": ca&.owner_type,
          "gh.gitauth.ssh_cert.owner_id": ca&.owner_id,
        })
        return
      end

      ca_id = ca.id

      owner_type, owner_id = ApplicationRecord::Collab.connection.select_rows(Arel.sql(<<-SQL, id: ca_id)).first
        SELECT owner_type, owner_id
        FROM ssh_certificate_authorities
        WHERE id = :id
      SQL

      # since we can't scope the ssh_certificate_authorities query above by tenant/business directly,
      # we need to check afterwards using the business id or org id (based on owner type)
      if GitHub.multi_tenant_enterprise?
        if owner_type == "Business"
          tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
          return unless owner_id == tenant_id
        else
          # this will automatically be scoped by the CurrentTenant
          return unless Organization.where(id: owner_id).exists?
        end
      end

      new(
        owner_is_eligible_for_feature: ca.owner_is_eligible_for_feature?,
        owner_name_and_type: ca.owner_name_and_type,
        id: ca_id,
        owner_type: owner_type,
        owner_id: owner_id,
        max_ssh_cert_lifetime_hours: ca.max_ssh_cert_lifetime_hours,
        can_access_user_owned_repositories: ca.owner_type == "Business" && ca.owner.ssh_certificate_user_owned_repo_access_enabled?
      )
    end

    def self.get_valid_id_extensions
      # Certificate extension names are suffixed with the "originating author or
      # organisation's domain name".
      id_ext = ["id@github.com"]

      if GitHub.multi_tenant_enterprise?
        # In proxima we don't want to allow id@github.com
        id_ext.shift
        id_ext.unshift("id@#{GitHub.host_name_with_tenant}")
      elsif GitHub.enterprise?
        id_ext.unshift("id@#{GitHub.host_name}")
      end

      id_ext
    end

    def self.get_valid_login_extensions
      if GitHub.multi_tenant_enterprise?
        return ["login@#{GitHub.host_name_with_tenant}"]
      end

      # Certificate extension names are suffixed with the "originating author or
      # organisation's domain name".
      login_ext = ["login@github.com"]
      login_ext.unshift("login@#{GitHub.host_name}") if GitHub.enterprise?

      login_ext
    end

    attr_accessor :user_id
    attr_reader :owner_name_and_type, :id, :owner_type, :owner_id, :max_ssh_cert_lifetime_hours, :can_access_user_owned_repositories

    def initialize(owner_is_eligible_for_feature:, owner_name_and_type:, id:, owner_type:, owner_id:, max_ssh_cert_lifetime_hours:, can_access_user_owned_repositories:)
      @owner_is_eligible_for_feature = owner_is_eligible_for_feature
      @owner_name_and_type = owner_name_and_type
      @id = id
      @owner_type = owner_type
      @owner_id = owner_id
      @max_ssh_cert_lifetime_hours = max_ssh_cert_lifetime_hours
      @can_access_user_owned_repositories = can_access_user_owned_repositories
    end

    def owner_is_eligible_for_feature?
      @owner_is_eligible_for_feature
    end

    # Check if this CA is owned by an org with a given id,
    # or a business associated with the org.
    #
    # org_id - the id of the Organization
    #
    # Returns boolean.
    def owned_by_organization_or_associated_business?(org_id)
      if owner_type == "Business"
        ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(<<-SQL, business_id: owner_id, organization_id: org_id))
          SELECT 1
          FROM business_organization_memberships
          WHERE business_id = :business_id
          AND organization_id = :organization_id
        SQL
      else
        owner_id == org_id
      end
    end

    # Check if this CA is owned by a business with a given id.
    #
    # business_id - the id of the Business
    #
    # Returns boolean.
    def owned_by_business?(business_id)
      owner_type == "Business" && owner_id == business_id
    end

    # Is this CA owned by the same entity as owns the given repository?
    #
    # repo - A Repository instance.
    #
    # Returns boolean.
    def owned_by_repo_owner?(repo)
      return false unless repo.owner.is_a?(Organization)

      owned_by_organization_or_associated_business?(repo.owner_id)
    end

    # Are certs signed by this CA allowed to access user-owned repositories?
    #
    # Returns boolean.
    def can_access_user_owned_repositories?
      @can_access_user_owned_repositories
    end
  end
end
