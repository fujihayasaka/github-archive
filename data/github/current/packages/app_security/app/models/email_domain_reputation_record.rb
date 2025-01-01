# typed: true
# frozen_string_literal: true

# EmailDomainReputationRecord exposes a public API for determining reputation for an email domain
# in our systems.
#
# > EmailDomainReputationRecord.metadata("sam@okstate.edu")
# => {
#      email_domains: ["okstate.edu", "connorsstate.edu"],
#      mx_exchanges: ["mailhost07.okstate.edu", "mailhost08.okstate.edu"],
#      a_records: ["139.78.133.12", "139.78.133.13"],
#    }
#
# > EmailDomainReputationRecord.reputation("jonmagic@mailinator.com")
# => {
#      reputation: 0.09,
#      reputation_lower_bound: 0.01,
#      sample_size: 123456,
#      not_spammy_sample_size: 42,
#    }
#
# Under the hood it's an ActiveRecord model designed to track relationships between
# email domains, MX exchanges, and A records along with the sample sizes needed to calculate
# the reputation for a set of associated domains.
class EmailDomainReputationRecord < ApplicationRecord::Collab
  extend T::Sig
  # Public: Get metadata for an email address or domain name. This includes all associated MX
  # exchanges, A records, and email domains.
  #
  # address - String email address or domain name.
  # address_type: Query by :email_domain, :mx_exchange, or :a_record. Default is :email_domain.
  #
  # Returns a Hash with email_domains, mx_exchanges, and a_records.
  def self.metadata(address, address_type: :email_domain)
    ActiveRecord::Base.connected_to(role: :reading) do
      domain = normalize_domain(address)

      domains = case address_type
      when :email_domain
        [domain]
      when :mx_exchange
        where(mx_exchange: address).limit(1000).pluck(:email_domain)
      when :a_record
        where(a_record: address).limit(1000).pluck(:email_domain)
      else
        raise InvalidAddressType.new(address_type)
      end

      associated_domain_a_records = where(email_domain: domains).pluck(:a_record)
      records = where(a_record: associated_domain_a_records).limit(1000)
      has_valid_public_suffix = if address_type == :email_domain
        PublicSuffix.valid?(domain, default_rule: nil, ignore_private: true)
      else
        nil
      end

      {
        email_domains: records.map(&:email_domain).sort.uniq.compact,
        mx_exchanges: records.map(&:mx_exchange).sort.uniq.compact,
        a_records: records.map(&:a_record).sort.uniq.compact,
        has_valid_public_suffix: has_valid_public_suffix,
      }
    end
  end

  # Public: Get reputation data for an email address or domain name.
  #
  # address - String email address or domain name.
  # address_type: Query by :email_domain, :mx_exchange, or :a_record. Default is :email_domain.
  #
  # Returns a Hash with reputation, reputation_lower_bound, sample_size, and not_spammy_sample_size.
  def self.reputation(address, address_type: :email_domain)
    ActiveRecord::Base.connected_to(role: :reading) do
      record = case address_type
      when :email_domain
        domain = normalize_domain(address)
        where(email_domain: domain).first
      when :mx_exchange
        where(mx_exchange: address).first
      when :a_record
        where(a_record: address).first
      else
        raise InvalidAddressType.new(address_type)
      end

      return Spam::Reputation.default if record.nil?

      Spam::Reputation.generate(sample_size: record.sample_size, not_spammy_sample_size: record.not_spammy_sample_size)
    end
  end

  # Public: Has this email domain been seen before?
  #
  # address - String email address or domain name.
  #
  # Returns true or false.
  def self.exists?(address)
    ActiveRecord::Base.connected_to(role: :reading) do
      domain = normalize_domain(address)
      where(email_domain: domain).exists?
    end
  end

  # Public: Recent users that signed up with or added an email that use this email domain.
  #
  # address - String email address or domain name.
  # since: How far back to look for users that recently added email addresses with this domain name.
  # limit: The maximum number of User to return.
  #
  # Returns an Array of User.
  def self.recent_users(address, since: 1.hour.ago, limit: 10)
    ActiveRecord::Base.connected_to(role: :reading) do
      domain = normalize_domain(address)
      User.
        newest_to_oldest.
        joins(:emails).
        where("user_emails.normalized_domain = ?", domain).
        where("user_emails.created_at > ?", since).
        limit(limit).
        reverse
    end
  end

  # Public: Process an email address or domain and create records for the email domain, it's MX
  # exchanges, and it's A records and then store sample counts for all of the domains associated
  # through the MX exchanges and A records.
  #
  # address - String email address or domain name.
  def self.process(address)
    return unless GitHub.flipper[:email_domain_reputation_record].enabled?

    domain = normalize_domain(address)

    return if IGNORED_DOMAINS.include?(domain)

    start_time = Time.now
    new_record = !exists?(domain)

    a_records = lookup_records_and_prepare_rows(domain)
    calculate_and_store_sample_sizes(a_records, domain)

    if new_record
      throttle do
        GlobalInstrumenter.instrument("email_domain_reputation_record.create", {
          domain: domain,
          recent_users: recent_users(domain),
          metadata: metadata(domain),
          reputation: reputation(domain),
          calculation_ms: calculation_ms(start_time),
        })
      end
    end
  end

  # Public: Enqueue domain to be processed later. Returns early if feature is not enabled.
  #
  # address - String email address or domain name.
  def self.process_later(address)
    return unless GitHub.flipper[:email_domain_reputation_record].enabled?

    domain = normalize_domain(address)

    return if IGNORED_DOMAINS.include?(domain)

    ProcessEmailDomainForReputationDataJob.perform_later(domain)
  end

  # Internal: Lookup MX exchanges and A records for domain and ensure rows exist for every tuple.
  #
  # domain - String domain name.
  #
  # Returns an Array of String A records.
  def self.lookup_records_and_prepare_rows(domain)
    values = []
    a_records = []
    now = Time.now.utc
    mx_exchanges = lookup_mx_records(domain)

    (mx_exchanges.any? ? mx_exchanges : [domain]).each do |mx_exchange|
      lookup_a_records(mx_exchange).each do |a_record|
        a_records << a_record
        values << [domain.downcase, mx_exchange.downcase, a_record, now, now]
      end
    end

    return a_records if a_records.empty?

    # Make sure table has row for every tuple.
    ActiveRecord::Base.connected_to(role: :writing) do
      values.each_slice(100) do |slice|
        throttle do
          GitHub.dogstats.time "email_domain_reputation_record", tags: ["action:insert_ignore"] do
            self.connection.insert(Arel.sql(INSERT_IGNORE_SQL, values: Arel::Nodes::ValuesList.new(slice)))
          end
        end
      end
    end

    a_records
  end

  # Internal: Calculate and store sample sizes for set of A records.
  #
  # a_records - Array of String A records.
  # domain - Optional domain to add to set (useful for getting around replication delay).
  def self.calculate_and_store_sample_sizes(a_records, domain = nil)
    a_records = Array(a_records)
    return if a_records.empty?

    # Get all email domains that are associated with the A record.
    email_domains = ActiveRecord::Base.connected_to(role: :reading) do
      GitHub.dogstats.time "email_domain_reputation_record", tags: ["action:top_email_domains"] do
        subqueries = Array(a_records).map { |a_record| self.connection.to_sql(Arel.sql(TOP_DOMAINS_BY_A_RECORD_ORDER_BY_DESC, a_record: a_record)) }
        query = <<-SQL
          SELECT email_domain FROM (
          #{subqueries.join("\nUNION\n")}
          ) AS subquery_for_limit ORDER BY sample_size DESC LIMIT 100
        SQL
        self.connection.select_rows(query).flatten
      end
    end
    email_domains = email_domains | [domain] if domain.present?

    # Get sample sizes used to calculate reputation.
    not_spammy_sample_size, sample_size = sample_sizes_for_domains(email_domains)

    # Update all records associated for this set of email domains.
    ActiveRecord::Base.connected_to(role: :writing) do
      email_domains.each_slice(100) do |slice|
        throttle do
          GitHub.dogstats.time "email_domain_reputation_record", tags: ["action:insert_ignore"] do
            self.connection.update(Arel.sql(UPDATE_REPUTATION_WHEN_CHANGED_SQL,
              email_domains: slice,
              sample_size: sample_size,
              not_spammy_sample_size: not_spammy_sample_size,
            ))
          end
        end
      end
    end
  end

  # Internal: Get sample sizes used to calculate reputation for a set of domains.
  #
  # domains - Array of String domain names.
  #
  # Array with Integer not_spammy_sample_size and Integer sample_size.
  def self.sample_sizes_for_domains(domains)
    results = ActiveRecord::Base.connected_to(role: :reading) do
      subqueries = Array(domains).map { |domain| User.connection.to_sql(Arel.sql(USER_IDS_SQL, domain: domain)) }

      query = <<-SQL
        SELECT user_id FROM (
        #{subqueries.join("\nUNION\n")}
        ) subquery_for_limit ORDER BY user_id DESC LIMIT 10000
      SQL

      GitHub.dogstats.time "email_domain_reputation_record", tags: ["action:counts"] do
        user_ids = UserEmail.connection.select_rows(query).flatten

        if user_ids.empty?
          [[0, 0]]
        else
          User.connection.select_rows(Arel.sql(COUNTS_SQL, user_ids: user_ids))
        end
      end
    end

    non_spammy_sample_size, sample_size = results.first

    [non_spammy_sample_size || 0, sample_size || 0]
  end

  # Internal: Lookup MX exchanges for a given domain.
  #
  # domain - String domain name.
  #
  # Returns an Array of String.
  def self.lookup_mx_records(domain)
    return @cached_mx_record_lookups[domain] if defined?(@cached_mx_record_lookups) && @cached_mx_record_lookups[domain].present?

    @cached_mx_record_lookups ||= {}
    @cached_mx_record_lookups[domain] = DNS_RESOLVER.getresources(domain, Resolv::DNS::Resource::IN::MX).map(&:exchange).map(&:to_s)
  end

  # Internal: Lookup A records for a given domain.
  #
  # domain - String domain name.
  #
  # Returns an Array of String.
  def self.lookup_a_records(domain)
    return @cached_a_record_lookups[domain] if defined?(@cached_a_record_lookups) && @cached_a_record_lookups[domain].present?

    @cached_a_record_lookups ||= {}
    @cached_a_record_lookups[domain] = DNS_RESOLVER.getresources(domain, Resolv::DNS::Resource::IN::A).map(&:address).map(&:to_s)
  end

  # Internal: Get domain name from email address.
  #
  # domain - String domain name.
  #
  # Returns a String.
  def self.normalize_domain(address)
    VerifiableDomain.normalize_domain(address)
  end

  sig { params(start_time: Time).returns(Integer) }
  def self.calculation_ms(start_time)
    ((Time.now - start_time) * 1000).to_i
  end

  # For testing purposes, where we want deterministic behaviour
  def self.clear_caches
    remove_instance_variable :@cached_a_record_lookups if defined?(@cached_a_record_lookups)
    remove_instance_variable :@cached_mx_record_lookups if defined?(@cached_mx_record_lookups)
  end

  # Resolv instance with retry and exponential backoff.
  DNS_RESOLVER = Resolv::DNS.new.tap { |resolver| resolver.timeouts = [0.5, 1, 2] }

  # Domains that we don't calculate a reputation for.
  IGNORED_DOMAINS = [
    "noreply.github.com",
    "users.noreply.github.com",
  ]

  # This query is used to ensure that a row exists for every email_domain,mx_exchange,a_record tuple.
  INSERT_IGNORE_SQL = <<-SQL
    INSERT IGNORE INTO
      email_domain_reputation_records
      (email_domain,mx_exchange,a_record,created_at,updated_at)
    :values
  SQL

  # This query gets 100,000 of the most recently created user ids associated with these email domains.
  USER_IDS_SQL = <<-SQL
    (SELECT DISTINCT user_id FROM user_emails WHERE user_emails.normalized_domain = :domain ORDER BY user_id DESC LIMIT 10000)
  SQL

  TOP_DOMAINS_BY_A_RECORD_ORDER_BY_DESC = <<-SQL
    (SELECT DISTINCT email_domain, sample_size FROM email_domain_reputation_records WHERE a_record = :a_record ORDER BY sample_size DESC, email_domain DESC LIMIT 100)
  SQL

  # This query is used to get sample counts for the users associated with a set of domains.
  COUNTS_SQL = <<-SQL
    SELECT
      cast(sum(case when spammy then 0 else 1 end) AS unsigned) AS non_spammy_count,
      count(id) AS n
    FROM users
    WHERE id IN (:user_ids)
  SQL

  # This query is used to update the sample counts for a set of domains when their sample sizes have changed.
  UPDATE_REPUTATION_WHEN_CHANGED_SQL = <<-SQL
    UPDATE email_domain_reputation_records
    SET
      sample_size = :sample_size,
      not_spammy_sample_size = :not_spammy_sample_size,
      updated_at = now()
    WHERE
      email_domain IN (:email_domains)
    AND
      (sample_size != :sample_size OR not_spammy_sample_size != :not_spammy_sample_size)
  SQL

  class InvalidAddressType < StandardError; end
end
