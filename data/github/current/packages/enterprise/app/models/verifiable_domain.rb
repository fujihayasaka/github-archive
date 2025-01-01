# typed: true
# frozen_string_literal: true

require "dns_resolver_monkey_patches"

class VerifiableDomain < ApplicationRecord::Ballast
  self.table_name = :organization_domains

  include GitHub::RateLimitable
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  VALID_OWNER_TYPES = %w(User Business).freeze
  AUDIT_LOG_EVENT_PREFIXES = {
    "User"        => "organization_domain",
    "Business"    => "enterprise_domain"
  }
  MAX_TXT_RECORD_LENGTH = 63
  NEW_TXT_RECORD_FORMAT_CUTOFF_DATE = Time.utc(2024, 4, 10)

  belongs_to :owner, polymorphic: true

  before_validation :normalize_domain
  validates_presence_of :owner, :domain
  validates :domain, length: { maximum: 255 }, unicode3: true
  validates_uniqueness_of :domain,
    scope: :owner,
    message: "has already been claimed",
    case_sensitive: false,
    if: proc { T.bind(self, VerifiableDomain); GitHub::UTF8.valid_unicode3?(domain) }
  validates :owner_type, inclusion: VALID_OWNER_TYPES
  validate :valid_domain, :not_homograph, :validate_organization_owner_for_user_owner_type

  after_create :generate_verification_token
  before_destroy :ensure_domain_not_required_for_policy

  after_create_commit :instrument_create
  after_destroy_commit :instrument_destroy
  after_destroy_commit :destroy_verification_token

  scope :verified, -> { where(verified: true) }
  scope :unverified, -> { where(verified: false) }
  scope :approved, -> { where(approved: true) }
  scope :unapproved, -> { where(approved: false) }
  scope :verified_or_approved, -> { verified.or(approved) }
  scope :usable_for, ->(object) {
    case object
    when Organization
      if object.business.present?
        usable_for(object.business).or(where(
          owner_type: object.class.base_class.name,
          owner_id: object.id,
        ))
      else
        where(
          owner_type: object.class.base_class.name,
          owner_id: object.id,
        )
      end
    when Business
      where(
        owner_type: object.class.base_class.name,
        owner_id: object.id,
      )
    end
  }
  scope :filtered_by_type, ->(include_verified, include_approved) {
    if include_verified && include_approved
      verified_or_approved
    elsif include_verified
      verified
    elsif include_approved
      approved
    else
      none
    end
  }

  VERIFY_ATTEMPTS_LIMIT = 10
  VERIFY_ATTEMPTS_LIMIT_TTL = 1.hour

  def self.normalize_domain(domain)
    return unless domain
    normalized_domain = domain.dup
    normalized_domain = normalized_domain.rpartition("@").last if normalized_domain.include?("@")
    normalized_domain.prepend("http://") unless normalized_domain =~ %r{\Ahttps?://}
    Addressable::IDNA.to_unicode(Addressable::URI.parse(normalized_domain).normalize.host)
  rescue Addressable::URI::InvalidURIError
    normalized_domain
  end

  def token_key(id = owner_id, type = owner_type)
    prefix = "#{type}." if type != "User"
    "domain_verification.#{prefix}#{id}.#{domain}"
  end

  def rate_limit_key
    prefix = "#{owner_type}." if owner_type != "User"
    "verify_org_domain_attempt.#{prefix}#{owner_id}.#{domain}"
  end

  def async_verification_token
    async_owner.then do |owner|
      verification_token(owner.id, owner_type)
    end
  end

  def verification_token(id = owner_id, type = owner_type)
    GitHub.kv.get(token_key(id, type)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def generate_verification_token
    if self.verified?
      errors.add(:base, "Domain is already verified.")
      false
    elsif verification_token.present?
      errors.add(:base, "Verification token is already present.")
      false
    else
      token = SecureRandom.hex(5)
      GitHub.kv.set(token_key, token, expires: 1.week.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      true
    end
  end

  def async_token_expiration_time
    async_owner.then do |owner|
      GitHub.kv.ttl(token_key(owner.id, owner_type)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end

  # Public: Manually set the expiration time for the verification token.
  # Currently only designed to be performed by site admins.
  #
  # If the expiration time was set successfully set, the return value is an
  # empty Array. If any errors occur, the return value contains the errors.
  #
  # expires_at - String containing the expiration time in the format YYYY-MM-DD.
  # actor - User performing the action.
  #
  # Returns Array of String containing any errors that occurred.
  def set_token_expiration_time(expires_at, actor:)
    errors  = []

    if verification_token.blank?
      errors << "No verification code was found for this domain"
    else
      if valid_token_expiration_time?(expires_at)
        expires_at_time = Date.parse(expires_at.to_s).to_time
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.set(
          token_key,
          verification_token,
          expires: expires_at_time
        )
        # rubocop:enable GitHub/DoNotUseGlobalKv

        payload = event_payload.merge(GitHub.guarded_audit_log_staff_actor_entry(actor))
        payload = payload.merge(token_expires_at: expires_at_time)
        GitHub.instrument "staff.set_domain_token_expiration", payload
      else
        errors << "Verification code expiry time must be a valid date in the future"
      end
    end

    errors
  end

  def async_dns_host_name
    async_owner.then do |_owner|
      dns_host_name
    end
  end

  def dns_host_name
    if use_new_txt_record_format?
      "_gh-#{txt_environment_modifier}#{txt_owner_modifier}.#{punycode_encoded_domain}"
    else
      host_name = "_github-challenge-#{txt_environment_modifier}#{txt_owner_modifier}.#{punycode_encoded_domain}"
      if full_txt_record.length > MAX_TXT_RECORD_LENGTH
        truncated_owner_modifier = txt_owner_modifier(truncate: true, reserved_length: reserved_length)
        return "_github-challenge-#{txt_environment_modifier}#{truncated_owner_modifier}.#{punycode_encoded_domain}"
      end
      host_name
    end
  end

  def dns_txt_key_copy_challenge
    if use_new_txt_record_format?
      "_gh-#{txt_environment_modifier}#{txt_owner_modifier}.#{parsed_domain.trd}".chomp(".")
    else
      if full_txt_record.length > MAX_TXT_RECORD_LENGTH
        truncated_owner_modifier = txt_owner_modifier(truncate: true, reserved_length: reserved_length)
        return "_github-challenge-#{txt_environment_modifier}#{truncated_owner_modifier}.#{parsed_domain.trd}".chomp(".")
      end
      full_txt_record
    end
  end

  def domain_string_for_challenge
    parsed_domain.domain
  end

  def async_host_name_found?
    async_dns_records.then do |records|
      records.any?
    end
  rescue Resolv::ResolvError, Resolv::ResolvTimeout
    Promise.resolve(false)
  end

  def host_name_found?
    async_host_name_found?.sync
  end

  def async_verification_token_found?
    async_dns_records.then do |records|
      records.any? { |r| r.strings.first == verification_token }
    end
  rescue Resolv::ResolvError, Resolv::ResolvTimeout
    Promise.resolve(false)
  end

  def verification_token_found?
    async_verification_token_found?.sync
  end

  # Public: attempt to verify the domain (check if the required DNS record exists). If an error
  # occurs and the domain cannot be verified, we'll record a Hydro event with the error. If the
  # domain is successfully verified, DomainVerificationNoticeJob will notify org members that
  # admins can now see their email addresses from this domain.
  #
  # actor           - user taking the action
  # staff_action    - true if this is a stafftools request
  # request_timeout - the timeout length (in seconds) that we are going to set for the DNS resolver
  #
  # Returns: Boolean
  def verify(actor:, staff_action: false, request_timeout: GitHub.default_request_timeout)
    error_code = if verified?
      errors.add(:base, "Domain has already been verified.")
      :already_verified
    elsif rate_limited?
      errors.add(:base, "You've reached the maximum number of verification attempts. Please try again later.")
      :rate_limited
    else
      begin
        if verification_dns_record_exists?(request_timeout)
          update_attribute(:verified, true)
          destroy_verification_token

          instrument_verify(actor, staff_action)

          if displays_verified_domain_emails?
            DomainVerificationNoticeJob.perform_later(owner, domain, "verified")
          end

          nil
        else
          :dns_record_not_found
        end
      rescue Resolv::ResolvError
        errors.add(:base, "We couldn't find the TXT record. Note that DNS changes can take up to 72 hours.")
        :dns_resolve_error
      rescue Resolv::ResolvTimeout, SocketError, StandardError
        errors.add(:base, "An error occurred while verifying this DNS record.")
        :dns_error
      end
    end

    GlobalInstrumenter.instrument("verifiable_domains.domain_verify_attempt", {
      domain: self,
      actor: actor,
      error: error_code,
      staff_action: staff_action
    })

    error_code.nil?
  end

  # Public: un-verify this domain. Should only be called via a stafftools action. Will not
  # unverify the domain if it's required for a notifications restriction policy that's
  # currently enabled.
  #
  # actor   -   user taking the action
  #
  # Returns: Boolean (success/failure)
  def unverify(actor:)
    unless verified?
      errors.add(:base, "Cannot unverify a domain that is not verified.")
      return false
    end

    if required_for_policy_enforcement?
      errors.add(:base, "Cannot unverify a domain that is required to enforce an #{owner_description} policy.")
      return false
    end

    destroy_verification_token
    update_attribute(:verified, false)
    instrument_unverify(actor: actor)
    true
  end

  # Public: approve this domain, so emails on this domain can also receive notifications
  #
  # actor   - user taking the action
  #
  # Returns: Boolean (success/failure)
  def approve(actor:)
    if approved?
      errors.add(:base, "Domain has already been approved.")
      return false
    end

    update_attribute(:approved, true)
    instrument_approve(actor)

    if VerifiableDomain.approved_domain_emails_visible_to_admins?
      DomainVerificationNoticeJob.perform_later(owner, domain, "approved")
    end

    true
  end

  # Public: checks if viewer has admin rights to the owner of this domain (Organization or Business)
  #
  # viewer    - user to check
  #
  # Returns: Boolean
  def adminable_by?(viewer)
    return false unless viewer
    owner.adminable_by?(viewer)
  end

  def default_resolver
    return @default_resolver if defined? @default_resolver

    @default_resolver = Resolv::DNS.new
    timeout = dns_timeout(GitHub.default_request_timeout)
    @default_resolver.timeouts = timeout if timeout > 0

    @default_resolver
  end

  # Public: Get the authoritative nameservers, which include both the default
  # nameservers plus the domain specific nameservers for this domain.
  #
  # Returns Array of String
  def authoritative_nameservers
    return @authoritative_nameservers if defined? @authoritative_nameservers

    # Include default nameservers
    @authoritative_nameservers = default_nameservers

    # Find authoritative nameservers for this domain
    found = begin
      default_resolver.getresources(punycode_encoded_domain, Resolv::DNS::Resource::IN::NS).map do |record|
        next record.name.to_s if record.is_a?(Resolv::DNS::Resource::IN::NS)
      end.compact
    rescue Resolv::ResolvTimeout
      []
    end

    @authoritative_nameservers.unshift *found
  end

  def dns_resolver(request_timeout: GitHub.default_request_timeout)
    return @dns_resolver if defined? @dns_resolver

    # Create a new DNS resolver based on the domain-specific and default nameservers
    @dns_resolver = Resolv::DNS.new(nameserver: authoritative_nameservers)
    timeout = dns_timeout(request_timeout)
    @dns_resolver.timeouts = timeout if timeout > 0

    @dns_resolver
  end

  def punycode_encoded_domain
    Addressable::IDNA.to_ascii(domain)
  end

  # Public: Is this domain required to exist to enforce a policy in an organization or enterprise?
  #
  # Returns a Promise<Boolean>.
  def async_required_for_policy_enforcement?
    return Promise.resolve(false) unless eligible_for_emails?

    async_owner.then do |owner|
      promises = [
        owner.async_restrict_notifications_to_verified_domains?,
        owner.async_email_eligible_domains,
      ]

      Promise.all(promises).then do |notification_restriction_enabled, email_eligible_domains|
        # If notifications are restricted and this is the only verified or approved domain,
        # this domain is required to exist for that policy to function.
        notification_restriction_enabled && email_eligible_domains.count == 1
      end
    end
  end

  # Public: sync version of async_required_for_policy_enforcement?
  def required_for_policy_enforcement?
    async_required_for_policy_enforcement?.sync
  end

  # Public: Check to see if this is the last verified domain for an enterprise, which does not have
  # notification restrictions enabled. If it is, and member organizations have notification
  # restriction policies enabled, those policies may be dependent on this domain.
  #
  # Returns: Boolean.
  def maybe_required_for_org_policy_enforcement?
    # not applicable to Organization-owned domains
    return false unless owner.is_a?(Business)

    # notification restriction policies only rely on verified or approved domains
    return false unless eligible_for_emails?

    # if the policy is enabled by the Enterprise itself, then required_for_policy_enforcement?
    # will capture it
    return false if owner.restrict_notifications_to_verified_domains?

    # see if any member organizations have enabled notification restrictions
    return false if Configuration::Entry.named("restrict_notification_delivery")
                                        .with_true_value
                                        .targeting_user_ids(owner.organization_ids).empty?

    # Warn if this is the only verified or approved domain for the Business - member organizations
    # can enable a notification restrictions policy without having any verified or approved domains
    # of their own, as long as the parent Enterprise has at least one verified or approved domain.
    owner.verifiable_domains.verified_or_approved.count == 1
  end

  # Public: Disables any enforcement policies that depend on this domain.
  #
  # actor - The User who is disabling the policies.
  #
  # Returns: nothing
  def disable_dependent_policies(actor:)
    notifications_restricted = owner.restrict_notifications_to_verified_domains?
    return if owner.is_a?(Organization) && !notifications_restricted

    if required_for_policy_enforcement?
      owner.disable_notification_restrictions(actor: actor)
    end

    if owner.is_a?(Business) &&
      VerifiableDomain.usable_for(owner).verified_or_approved.without(self).empty?
      UpdateBusinessOrgsNotificationRestrictionsJob.perform_later(
        owner.id,
        actor.id,
        self.id,
        notifications_restricted: notifications_restricted
      )
    end
  end

  # Public: generate the stafftools audit log query for this domain. Parameterization for the query:
  #  - the id clause: in the olden days when domains could only be attached to Organizations,
  #                   the id field was called `organization_domain_id`. Now that a domain can be
  #                   attached to an Organization or a Business, the id field has been renamed to
  #                   `verifiable_domain_id`. Query for both to make sure to get all the events.
  #  - the action clause: same as id, when the domains could only be attached to Organizations, the
  #                       event prefix was always `organization_domain`. Now, Business-owned domains
  #                       get an `enterprise_domain` prefix
  #
  # Returns: audit log query (String)
  def domain_audit_log_query
    id_query = "data.verifiable_domain_id:#{id}"
    id_query = "(data.organization_domain_id:#{id} OR #{id_query})" if owner.is_a?(Organization)
    action_query = "(action:#{event_prefix}.* OR action:staff.*verify_domain)"
    "#{id_query} AND #{action_query}"
  end

  def domain_audit_log_kql_query
    id_query = "webevents | where data.verifiable_domain_id == '#{id}'"
    id_query += " or data.organization_domain_id == '#{id}'" if owner.is_a?(Organization)
    action_query = "(action startswith '#{event_prefix}' or action matches regex 'staff.*verify_domain')"
    "#{id_query} and #{action_query}"
  end

  def owner_description
    return "enterprise" if owner_type == "Business"
    "organization"
  end

  # Public: check if the current domain corresponds to one of the profile domains for the owner.
  # If the owner is an org, just check that org. If the owner is a business, check each of its
  # organizations, and return all that matched.
  #
  # Returns: Array[Organization]
  def organizations_for_profile_domain
    organizations = case owner
    when Business
      owner.organizations.includes(:profile)
    when Organization
      [owner]
    end

    organizations.select do |org|
      profile_domains = [org.profile_blog, org.profile_email].compact.reject(&:blank?)
      normalized_domains = profile_domains.map do |profile_domain|
        VerifiableDomain.normalize_domain(profile_domain)
      end
      normalized_domains.include?(domain)
    end
  end

  # Public: see if this domain is eligible to receive emails. Returns true if the domain
  # has been either verified or approved.
  #
  # Returns: Boolean
  def eligible_for_emails?
    verified? || approved?
  end

  # Public: class method to determine if org admins are allowed to see users' approved domain
  # email addresses for an org in a given environment. Due to privacy concerns, approved domain
  # emails are not visible to org admins on the dotcom environment since an enterprise owner or
  # org admin could approve a domain associated with private emails such as gmail.com and this
  # would enable then to see email addresses associated with users' personal accounts. However,
  # on GHES, since entities owning the enterprises there control the user accounts, it's
  # reasonable for org admins to see approved domain emails.
  #
  # Returns true for a single business environment, false otherwise.
  def self.approved_domain_emails_visible_to_admins?
    GitHub.single_business_environment?
  end

  def use_new_txt_record_format?
    return unless created_at.present?
    T.must(created_at) > NEW_TXT_RECORD_FORMAT_CUTOFF_DATE
  end

  private

  def txt_environment_modifier
    return "ghes-" if GitHub.enterprise?
    return "ghe-" if GitHub.multi_tenant_enterprise?
  end

  def stamp
    return GitHub.heaven_env if GitHub.multi_tenant_enterprise?
  end

  def txt_owner_modifier(truncate: false, reserved_length: 0)
    if use_new_txt_record_format?
      owner_suffix = owner.is_a?(Business) ? "e" : "o"
      reserved_length = "_gh-#{txt_environment_modifier}#{owner_suffix}.#{parsed_domain.trd}".chomp(".").length
      available_owner_param_length = MAX_TXT_RECORD_LENGTH - reserved_length

      if available_owner_param_length.positive?
        owner_name = owner.to_param[0, available_owner_param_length].chomp("-")
        "#{owner_name}-#{owner_suffix}"
      else
        owner_suffix
      end
    else
      owner_name = if truncate
        owner.to_param[0, (MAX_TXT_RECORD_LENGTH - reserved_length)].chomp("-")
      else
        owner.to_param
      end

      owner.is_a?(Business) ? "#{owner_name}-ent" : "#{owner_name}-org"
    end
  end

  # Private: Get the portion of the TXT record without the top level to domain.
  #
  # Returns String
  def full_txt_record
    "_github-challenge-#{txt_environment_modifier}#{txt_owner_modifier}.#{parsed_domain.trd}".chomp(".")
  end

  # Private: Get the count of characters that are reserved for a TXT record.
  #
  # Returns Integer
  def reserved_length
    "_github-challenge-#{txt_environment_modifier}-ent.#{parsed_domain.trd}".chomp(".").length
  end

  # Private: Get the DNS query timeout value in seconds based on the given
  # request timeout value.
  #
  # This timeout is per authoritative nameserver, so the total timeout needs to be less than the
  # request timeout. Each request is tried once before moving on to the next nameserver.
  #
  # Assuming a domain has 10 authoritative nameservers, the total timeout will be:
  #
  # dotcom: 9.5s @ 0.475s per nameserver
  # ghes: 27.5s @ 1.375s per nameserver
  #
  # Returns Float
  def dns_timeout(request_timeout)
    ((request_timeout - 0.5) / 2) / authoritative_nameservers.length
  end

  # Private: Destroy the verification token if it exists.
  #
  # Returns nothing.
  def destroy_verification_token
    GitHub.kv.del(token_key) if verification_token.present? # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Private: Get the default nameservers detected by Resolv, filtering out any
  # that we never want to use.
  #
  # Returns Array of String
  def default_nameservers
    return @default_nameservers if defined? @default_nameservers

    @default_nameservers = filter_invalid_nameservers(Resolv::DNS::Config.default_config_hash[:nameserver])
  end

  # Private: Filter invalid nameservers out of the a given Array of nameservers.
  #
  # Filter out any IPv6 link-local addresses from nameservers (for example
  # "fe80::5cb0:3cff:fe51:29b0%eth0"), as they cause a major bug when used
  # for DNS queries with Resolv.
  #
  # More details in https://github.com/github/admin-experience/issues/1255
  #
  # Returns Array of String
  def filter_invalid_nameservers(nameservers)
    return [] unless nameservers.present?
    nameservers.reject do |ns|
      ns =~ /\A.*\%[a-zA-Z0-9]*\z/
    end
  end

  # Private: Check whether a given expires_at value is valid for a verification token.
  #
  # expires_at - String containing the expiration time in the format YYYY-MM-DD.
  #
  # Returns Boolean
  def valid_token_expiration_time?(expires_at)
    Date.parse(expires_at.to_s).to_time.future?
  rescue ArgumentError
    false
  end

  def event_prefix
    AUDIT_LOG_EVENT_PREFIXES[owner_type]
  end

  def async_dns_records
    async_owner.then do
      begin
        dns_resolver.getresources(dns_host_name, Resolv::DNS::Resource::IN::TXT).select do |record|
          record.is_a?(Resolv::DNS::Resource::IN::TXT)
        end
      rescue Resolv::ResolvError, Resolv::ResolvTimeout
        []
      end
    end
  end

  def rate_limited?
    return unless GitHub.rate_limiting_enabled?

    rate_limit_increment(
      rate_limit_key,
      { max_tries: VERIFY_ATTEMPTS_LIMIT, ttl: VERIFY_ATTEMPTS_LIMIT_TTL }
    ).at_limit?
  end

  def verification_dns_record_exists?(request_timeout)
    resolver = dns_resolver(request_timeout: request_timeout)
    records = resolver.getresources(dns_host_name, Resolv::DNS::Resource::IN::TXT).select do |record|
      record.is_a?(Resolv::DNS::Resource::IN::TXT)
    end

    if records.empty?
      errors.add(:base, "We couldn't find the TXT record. Note that DNS changes can take up to 72 hours.")
      false
    elsif records.any? { |r| r.strings.first == verification_token }
      true
    else
      errors.add(:base, "The TXT record did not match the verification code. Note that DNS changes can take up to 72 hours.")
      false
    end
  end

  def normalize_domain
    self.domain = VerifiableDomain.normalize_domain(domain)
  end

  # Private: Options to pass to PublicSuffix validation/parsing calls.
  #
  # See PublicSuffix source for more information:
  #
  # https://github.com/weppos/publicsuffix-ruby/blob/405c291c0eba7b0c42f276a30aad5f0a31d8613f/lib/public_suffix.rb#L29-L132
  #
  # Returns Hash.
  def public_suffix_options
    {
      default_rule: nil,
      ignore_private: true,
    }
  end

  # Private: Get the parsed domain by calling PublicSuffix.parse with
  # the appropriate options.
  #
  # Returns PublicSuffix::Domain
  def parsed_domain
    PublicSuffix.parse(domain, **public_suffix_options)
  end

  # Private: Validation method to validate the domain by calling
  # PublicSuffix.valid? with the appropriate options.
  #
  # Returns nothing.
  def valid_domain
    if domain.blank? || !PublicSuffix.valid?(domain, **public_suffix_options)
      errors.add(:domain, "is not a valid public domain.")
    end
  end

  def not_homograph
    if HomographDetector.homograph_attack?("http://" + Addressable::IDNA.to_unicode(domain))
      errors.add(:domain, "is not eligible for verification, as it is a potential homograph.")
    end
  end

  def validate_organization_owner_for_user_owner_type
    return if owner.nil?
    return unless owner_type == "User"

    unless owner.organization?
      errors.add(:owner, "must be an Organization when owner_type is User")
    end
  end

  def ensure_domain_not_required_for_policy
    if required_for_policy_enforcement?
      errors.add(:domain, "is required to enforce an #{owner_description} policy and cannot be deleted")
      throw :abort
    end
  end

  def displays_verified_domain_emails?
    return true if owner.is_a?(Business) && !owner.downgraded_to_free_plan?
    return true if owner.is_a?(Organization) && owner.plan_supports?(:display_verified_domain_emails)
    false
  end

  def event_payload
    domain_payload = {
      verifiable_domain: self,
      owner: owner,
      owner_type: owner_type,
      domain_name: self.domain,
    }
    if owner.is_a?(Business)
      domain_payload[:business] = owner
    else
      domain_payload[:org] = owner
      if owner.business.present?
        domain_payload[:business] = owner.business
      end
    end

    domain_payload
  end

  def instrument_create
    instrument :create

    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("verifiable_domains.domain_created", {
      domain: self,
      actor: actor
    })
  end

  def instrument_verify(actor, staff_actor = false)
    if staff_actor
      guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      GitHub.instrument("staff.verify_domain", event_payload.merge(guarded_actor))
    else
      instrument :verify
    end
    InstrumentProfileDomainVerifiedJob.perform_later(self, actor)
  end

  # Only staff members can unverify domains
  def instrument_unverify(actor:)
    guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
    GitHub.instrument("staff.unverify_domain", event_payload.merge(guarded_actor))
    GlobalInstrumenter.instrument("verifiable_domains.domain_unverified", {
      domain: self,
      actor: actor
    })
  end

  def instrument_approve(actor)
    instrument :approve

    GlobalInstrumenter.instrument("verifiable_domains.domain_approved", {
      domain: self,
      actor: actor
    })
  end

  def instrument_destroy
    instrument :destroy

    actor = User.find_by(id: GitHub.context[:actor_id])
    GlobalInstrumenter.instrument("verifiable_domains.domain_deleted", {
      domain: self,
      actor: actor
    })
  end
end
