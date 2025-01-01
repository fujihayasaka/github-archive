# typed: false
# frozen_string_literal: true

require "github/pages/domain_health_checker"
require "openssl"
require "scientist"

class Page::Certificate < ApplicationRecord::Domain::PagesFromRepositories
  include GitHub::CacheLock
  include GitHub::Relay::GlobalIdentification
  include PagesHelper

  Error = Class.new(RuntimeError)

  # Errors that, when encountered during our flow, can be recovered from.
  RecoverableError = Class.new(Error)

  # Errors that, when encountered during our flow, cannot be recovered from.
  FatalError                 = Class.new(Error)
  DenylistedError            = Class.new(FatalError)
  FastlyNotEnabledError      = Class.new(FatalError)
  MissingDataError           = Class.new(FatalError)
  AttemptedDomainChangeError = Class.new(FatalError)
  LockedError                = Class.new(FatalError)
  InvalidAuthorizationError  = Class.new(FatalError)
  DomainError                = Class.new(FatalError)

  # How long before a cert's expiration we renew it.
  RENEWAL_WINDOW = 30.days
  # How long before a cert's expiration we renew it for balancing purposes.
  RENEWAL_BALANCING_MAX_EXPIRES_AT = 60.days

  PEM_REXP = /[-]+BEGIN CERTIFICATE[-]+.+?[-]+END CERTIFICATE[-]+/m

  STATE_DESCRIPTIONS = {
    new:                   "This domain was recently added. The certificate request process will begin shortly.",
    authorization_created: "Authorization created",
    authorization_pending: "Authorization verification pending.",
    authorized:            "Domain authorization succeeded.",
    authorization_revoked: "Authorization has been revoked.",
    issued:                "The certificate has been successfully issued.",
    uploaded:              "The certificate has been uploaded and is awaiting approval.",
    approved:              "The certificate has been approved.",
    errored:               "An error occurred.",
    bad_authz:             "The ACME authorization is in a bad state. We need to start over.",
    destroy_pending:       "Certificate is pending removal",
    dns_changed:           "Detected a change to DNS settings. Requesting a new certificate.",
    private_key_revoked:   "The private key has been revoked. This cert needs to be reissued.",
  }.freeze

  enum :state, {
    new:                   0,
    authorization_created: 1,
    authorization_pending: 2,
    authorized:            3,
    authorization_revoked: 4,
    issued:                5,
    uploaded:              6,
    approved:              7,
    errored:               8,
    bad_authz:             9,
    destroy_pending:       10,
    dns_changed:           11,
    private_key_revoked:   12,
  }, prefix: true

  def self.state_description(state)
    STATE_DESCRIPTIONS[state.to_sym]
  end

  def state_description
    self.class.state_description(current_state)
  end

  validates_presence_of :domain

  before_validation :fail_on_domain_change, on: :update
  before_validation :set_initial_state

  after_update :log_statechange, if: :saved_change_to_state?

  after_commit :begin_flow, on: [:create]

  before_destroy :delete_certificate_from_fastly

  # Is this domain configured correctly for us to obtain a certificate?
  #
  # domain_name - A String domain name.
  #
  # Returns boolean.
  def self.eligible?(domain_name)
    return false if domain_name.blank?
    return false if denylisted?(domain_name)
    GitHub::Pages::DomainHealthChecker.new(domain_name).https_eligible?
  end

  # Is this alternate domain configured correctly for us to obtain a certificate?
  #
  # alt_domain_name - A String domain name.
  #
  # Returns boolean.
  def self.alt_domain_eligible?(alt_domain_name)
    return false if denylisted?(alt_domain_name)
    return false if alt_domain_name.blank?
    GitHub::Pages::DomainHealthChecker.new(alt_domain_name).https_eligible?
  end

  # Is this domain denylisted?
  #
  # domain_name - a String domain name.
  #
  # Returns true if the domain is denylisted and a certificate must not be issued.
  def self.denylisted?(domain_name)
    GitHub.acme_denylist.any? { |entry| domain_name.end_with?(entry) }
  end

  # Internal: An unencoded string used to generate a global identifier for use
  # with GraphQL and Relay. See #global_relay_id below.
  def global_id
    "#{self.id}:#{Digest::SHA256.hexdigest(self.domain)}"
  end

  # Enqueue a job to begin the cert issuance/upload flow.
  #
  # Returns nothing.
  def begin_flow
    PageCertificateWorkJob.perform_later(id)
  end
  alias resume_flow begin_flow

  def preflight_acme!
    return unless GitHub.acme_enabled?
    GitHub.acme.clear_nonces
  end

  # Request a domain authorization from the ACME server.
  #
  # Returns nothing.
  def request_authorization
    check_domain!

    preflight_acme!
    if !GitHub.enterprise?
      alt_domain = get_alt_domain(domain) if alt_domain.blank?
      is_alt_domain_eligible = self.class.alt_domain_eligible?(alt_domain)
      identifiers = is_alt_domain_eligible ? [domain, alt_domain] : [domain]

      order = GitHub.acme.new_order(identifiers: identifiers)
      auth_domain = order.authorizations.find { |a| a.identifier["value"].eql? domain }
      challenge_domain = auth_domain.http

      update_state(:authorization_created,
        order_url: order.url,
        authorization_url: auth_domain.url,
        challenge_path: "/#{challenge_domain.filename}",
        challenge_response: challenge_domain.file_content,
      )

      if is_alt_domain_eligible
        auth_alt_domain = order.authorizations.find { |a| a.identifier["value"].eql? alt_domain }
        challenge_alt_domain = auth_alt_domain.http
        update_state(:authorization_created,
          alt_domain: alt_domain,
          alt_authorization_url: auth_alt_domain.url,
          alt_challenge_path: "/#{challenge_alt_domain.filename}",
          alt_challenge_response: challenge_alt_domain.file_content,
        )
      else
        # Clear alt domain information if not eligible anymore so we don't
        # try to verify an invalid alt authorization in the next step
        update_state(:authorization_created,
          alt_domain: nil,
          alt_authorization_url: nil,
          alt_challenge_path: nil,
          alt_challenge_response: nil,
        )
      end

      GitHub.dogstats.increment("pages.certificates.order", tags: [
        "num_identifiers:#{identifiers.length}"
      ])
    else
      order = GitHub.acme.new_order(identifiers: [domain])
      authorization = order.authorizations.first
      challenge = authorization.http

      update_state(:authorization_created,
        order_url: order.url,
        authorization_url: authorization.url,
        challenge_path: "/#{challenge.filename}",
        challenge_response: challenge.file_content,
      )
    end

    :proceed
  end

  # Request that the ACME server verify our authorization by making a request to
  # the domain.
  #
  # Returns nothing.
  def request_authorization_verification
    check_domain!

    preflight_acme!

    authorization = GitHub.acme.authorization(url: authorization_url)
    authorization.http.request_validation

    if !GitHub.enterprise? && alt_authorization_url.present?
      alt_authorization = GitHub.acme.authorization(url: alt_authorization_url)
      alt_authorization.http.request_validation
    end

    update_state(:authorization_pending, fastly_privkey_id: GitHub.fastly_private_key_id)

    :proceed
  end

  AUTH_STATUS_MAPPING = {
    #[Domain authorization status, alternate domain authorization status]
    %w[valid valid] => "valid",
    %w[valid invalid] => "invalid",

    %w[valid pending] => "pending",
    %w[valid revoked] => "revoked",

    %w[invalid invalid] => "invalid",
    %w[invalid valid] => "invalid",
    %w[invalid pending] => "invalid",
    %w[invalid revoked] => "revoked",

    %w[revoked revoked] => "revoked",
    %w[revoked valid] => "revoked",
    %w[revoked invalid] => "revoked",
    %w[revoked pending] => "revoked",

    %w[pending pending] => "pending",
    %w[pending invalid] => "invalid",
    %w[pending valid] => "pending",
    %w[pending revoked] =>  "revoked"
  }

  # Check if our authorization has been verified.
  #
  # Returns nothing.
  def check_authorization_verification
    preflight_acme!

    # Existing authorizations are tied to the private key used to create them.
    # If the private key has changed, we need to start over.
    if fastly_privkey_id != GitHub.fastly_private_key_id
      update_state(:private_key_revoked, fastly_privkey_id: GitHub.fastly_private_key_id)
      return :proceed
    end


    authorization = begin
      GitHub.acme.authorization(url: authorization_url)
    rescue Acme::Client::Error::NotFound
      # LE deletes pending authorizations after a days. At this point, we just
      # have to start over.
      update_state(:bad_authz)
      return :proceed
    end

    status = authorization.http.status

    if !GitHub.enterprise? && alt_authorization_url.present?
      alt_authorization = get_authorization(alt_authorization_url)
      status = AUTH_STATUS_MAPPING[[authorization.http.status, alt_authorization.http.status]]
    end

    case status
    when "valid"
      # Our authorization has been verified. We can move on to requesting a
      # certificate.
      update_state(:authorized)
      :proceed
    when "invalid"
      update_state(:bad_authz)
      :proceed
    when "pending"
      # The CA hasn't made the verification request yet. Check again later.
      :retry
    when "revoked"
      # We were authorized, but that's expired. Start over.
      update_state(:authorization_revoked)
      :proceed
    else
      # Could be "processing", which isn't currently used. Could be or
      # "deactivated", meaning that we explicitly canceled our authorization,
      # which should never happen. Either way, we'll retry to see if it resolves
      # itself.
      tags = ["domain:#{domain}",
              "primary_status:#{authorization.http.status}"]
      if !GitHub.enterprise? && alt_authorization_url.present?
        tags << "alt_status:#{alt_authorization.http.status}"
      end

      GitHub.dogstats.increment("pages.certificates.authorization_verification_retry", tags: tags)
      :retry
    end
  end

  # Request that a certificate be issued.
  #
  # Returns nothing.
  def request_certificate
    preflight_acme!

    # reference status from https://tools.ietf.org/html/draft-ietf-acme-acme-12#section-7.1.6
    order = GitHub.acme.order(order_url: order_url)
    if order.status == "valid"
      update_state(:issued,
        expires_at: OpenSSL::X509::Certificate.new(order.certificate).not_after,
        cert_chain: order.certificate,
        fastly_privkey_id: GitHub.fastly_private_key_id,
      )
    elsif order.status == "processing"
      # Certificate is under processing, check later.
      return :retry
    elsif order.status == "invalid"
      update_state(:bad_authz)
    elsif order.status == "ready"
      GitHub.dogstats.distribution_time("github.csr.dist", tags: ["method:local_csr"]) do
        cert_key = GitHub.acme_cert_key
        csr = OpenSSL::X509::Request.new
        csr.version = 0
        csr.subject = OpenSSL::X509::Name.new([["CN", domain]])

        # add SAN extension containing alt_domain to the CSR when feature flag is enabled
        if !GitHub.enterprise? && !alt_domain.blank?
          extensions = [
            OpenSSL::X509::ExtensionFactory.new.create_extension("subjectAltName", "DNS:#{alt_domain}")
          ]
          attribute_values = OpenSSL::ASN1::Set [OpenSSL::ASN1::Sequence(extensions)]
          [
            OpenSSL::X509::Attribute.new("extReq", attribute_values),
          ].each do |attribute|
            csr.add_attribute attribute
          end
        end

        csr.public_key = cert_key.public_key
        csr.sign cert_key, OpenSSL::Digest::SHA256.new

        order.finalize(csr: csr)
        update_state(:authorized)
      end
    end
    :proceed
  end

  # A certificate has been issued. Upload it to Fastly.
  #
  # Returns nothing.
  def upload_certificate
    raise FastlyNotEnabledError unless GitHub.fastly_enabled?

    unless pem_chain = parsed_detail["cert_chain"]
      # This should never happen.
      raise MissingDataError, "Missing cert chain"
    end

    chain = pem_chain.scan(PEM_REXP)
    cert_body = chain.shift
    cert_intermediate_body = chain.join("\n")

    if cert_body.nil? || cert_intermediate_body.nil?
      raise MissingDataError, "Missing cert or intermediate"
    end

    response = if fastly_certificate_id
      GitHub.dogstats.distribution_time("github.fastly.rpc.dist", tags: ["method:update_certificate"]) do
        GitHub.fastly.update_certificate(Fastly::Certificate.new({
            certificate_id:           fastly_certificate_id,
            certificate:              cert_body,
            certificate_intermediate: cert_intermediate_body,
            key_file:                 fastly_privkey_id,
          }),
        )
      end
    else
      GitHub.dogstats.distribution_time("github.fastly.rpc.dist", tags: ["method:upload_certificate"]) do
        GitHub.fastly.upload_certificate(Fastly::Certificate.new({
            certificate:              cert_body,
            certificate_intermediate: cert_intermediate_body,
            key_file:                 fastly_privkey_id,
          }),
        )
      end
    end

    if response.approved
      update_state(:approved, fastly_certificate_id: response.certificate_id)
      GitHub.dogstats.increment("pages.certificates", tags: ["state:approved"])
      :halt
    else
      update_state(:uploaded, fastly_certificate_id: response.certificate_id)
      GitHub.dogstats.increment("pages.certificates", tags: ["state:uploaded"])
      :proceed
    end
  end

  # The certificate has been uploaded to Fastly. Check if it's been approved.
  #
  # Returns nothing.
  def check_uploaded_certificate
    raise FastlyNotEnabledError unless GitHub.fastly_enabled?

    unless fastly_certificate_id
      # This should never happen.
      raise MissingDataError, "Missing Fastly certificate ID"
    end

    cert = GitHub.dogstats.distribution_time("github.fastly.rpc.dist", tags: ["method:get_certificate"]) do
      GitHub.fastly.get_certificate(certificate_id: fastly_certificate_id)
    end

    if cert.approved
      update_state(:approved)
      :halt
    else
      :retry
    end
  end

  # Can TLS be terminated with this certificate?
  #
  # Returns boolean.
  def usable?
    return false unless expires_at
    current_state == :approved && expires_at > Time.now
  end

  # Attempt to lock this record and call the given block.
  #
  # Returns the return value from the provided block. Raises LockedError if a
  # lock is already held elsewhere.
  def with_lock
    raise LockedError unless lock

    begin
      yield
    ensure
      unlock
    end
  end

  # Lock this record while performing work to prevent multiple jobs from
  # operating on the same record at the same time.
  #
  # Returns true if the lock was attained, false otherwise.
  def lock
    cache_lock_obtain("page-certificate:#{id}:lock")
  end

  # Unlock this record once done performing work.
  #
  # Returns nothing.
  def unlock
    cache_lock_release("page-certificate:#{id}:lock")
  end

  # Deletes the certificate from Fastly's servers & sets state such that re-upload is possible.
  #
  # If all is well, returns nothing.
  # Raises Fastly::CertificateDeletionError if it fails.
  def delete_certificate
    return unless fastly_certificate_id

    delete_certificate_from_fastly

    # This will move it back to a state where it could be re-issued & uploaded.
    update_state(:authorization_pending, fastly_certificate_id: nil)

    nil
  end

  # Swap the primary and the alternate domain on the certificate
  #
  # If certificate has already been issued for a domain and user comes back and
  # changes the cname to www variant of the already created certificate, we end
  # up in a situation where we have two records in the Page::Certificate. To avoid
  # this kind of duplication we check if there already is a record in the page::Certificate
  # table with the cname's alternate domain, if it exists we swap the values. We choose to swap
  # instead of deleting the old and create a new afresh to reduce downtime on the fastly end
  def flip_certificate
    @domain_flip = true

    if self.alt_domain.blank?
      GitHub.logger.info("flip_certificate: when alt_domain is blank", {
                          "gh.pages.domain" => self.domain,
                          "gh.pages.alternate.domain" => self.alt_domain })
      calc_alt_domain = get_alt_domain(self.domain)
      update!(
        state: :dns_changed,
        alt_domain: self.domain,
        domain: calc_alt_domain,
        authorization_url: nil,
        challenge_path: nil,
        challenge_response: nil,
        alt_authorization_url: self.authorization_url,
        alt_challenge_path: self.challenge_path,
        alt_challenge_response: self.challenge_response
      )
    else
      GitHub.logger.info("flip_certificate: when alt_domain is set", {
                          "gh.pages.domain" => self.domain,
                          "gh.pages.alternate.domain" => self.alt_domain
                          })

      new_state = current_state == :approved ? :approved : :new
      GitHub.logger.info("flip_certificate: check state", {
                          "gh.pages.domain" => self.domain,
                          "gh.pages.alternate.domain" => self.alt_domain,
                          "gh.pages.certificate.state" => new_state
                          })

      update!(
        state: new_state,
        alt_domain: self.domain,
        domain: self.alt_domain,
        authorization_url: self.alt_authorization_url,
        alt_authorization_url: self.authorization_url,
        challenge_path: self.alt_challenge_path,
        challenge_response: self.alt_challenge_response,
        alt_challenge_path: self.challenge_path,
        alt_challenge_response: self.challenge_response
      )
    end

    @domain_flip = false
  end

  # Delete the certificate from the database which also triggers #delete_certificate_from_fastly
  def destroy_certificate
    destroy!
    :halt
  end

  # Whether the certificate is due for renewal.
  def needs_renewal?
    return unless expires_at
    expires_at < RENEWAL_WINDOW.from_now
  end

  def days_before_expiration
    return nil unless expires_at.present?
    (expires_at.to_date - Date.today).to_i
  end

  # Reset the certificate back to the beginning of the flow.
  def reset_flow
    update_state(:bad_authz)
    :proceed
  end

  def current_state
    state.to_sym
  end

  def platform_type_name
    "PageCertificate"
  end

  ##
  # User object of the owner of the repository associated with a page having a matching domain.
  #
  # @return [User, nil]
  #
  def owner
    return @owner if defined?(@owner)
    @owner = repo&.owner
  end

  ##
  # Repository object of the repository associated with a page having a matching domain.
  #
  # @return [Repository, nil]
  #
  def repo
    return @repo if defined?(@repo)
    page = Page.find_by_cname(domain)
    @repo = page.repository unless page.nil?
  end

  def pem_rexp
    PEM_REXP
  end

  private

  def check_domain!
    raise DenylistedError if self.class.denylisted?(domain)
    raise DomainError unless self.class.eligible?(domain)
  end

  def update_state(state, other_fields = {})
    new_attrs = { state: state }

    [
      :alt_domain,
      :expires_at,
      :challenge_path,
      :challenge_response,
      :alt_challenge_path,
      :alt_challenge_response,
      :fastly_privkey_id,
      :authorization_url,
      :alt_authorization_url,
      :certificate_url,
      :fastly_certificate_id,
      :order_url
    ].each do |attr|
      if other_fields.key?(attr)
        new_attrs[attr] = other_fields.delete(attr)
      end
    end

    new_attrs[:state_detail] = other_fields.to_json

    # we may not have an `updated_at` for older certificates,
    # so check to make sure the column isn't empty first.
    if self.updated_at.present?
      time_in_state = Time.now - self.updated_at
      GitHub.dogstats.timing("pages.certificates.timings", time_in_state, tags: ["previous_state:#{self.state}", "new_state:#{state}"])
    end

    update!(new_attrs)
  end

  # We store a JSON serialized Hash of temporary state in the #state_detail
  # field. This method is a helper for accessing that data.
  #
  # Returns a Hash.
  def parsed_detail
    state_detail.nil? ? {} : JSON.parse(state_detail)
  end

  def set_initial_state
    self.state ||= :new
  end

  # Deletes the certificate from Fastly's servers.
  # Should ONLY be called on its own by Page::Certificate#destroy.
  #
  # If all is well, returns nothing.
  # Raises Fastly::CertificateDeletionError if it fails.
  def delete_certificate_from_fastly
    return unless fastly_certificate_id

    GitHub.dogstats.distribution_time("github.fastly.rpc.dist", tags: ["method:delete_certificate"]) do
      GitHub.fastly.delete_certificate(certificate_id: fastly_certificate_id)
    end
  end

  # Internal: Raise an error if the domain is changed.
  #
  # Returns nothing.
  def fail_on_domain_change
    if domain_changed? && !@domain_flip
      raise AttemptedDomainChangeError
    end
  end

  def get_authorization(url)
    authorization = begin
      GitHub.acme.authorization(url: url)
    rescue Acme::Client::Error::NotFound
      # LE deletes pending authorizations after a days. At this point, we just
      # have to start over.
      update_state(:bad_authz)
      return :proceed
    end
  end

  def log_statechange
    GitHub.logger.info("page certificate state updated", {
                       "gh.pages.certificate.id" => fastly_certificate_id,
                       "gh.pages.domain" => self.domain,
                       "gh.pages.alternate.domain" => self.alt_domain,
                       "gh.pages.certificate.state" => state_description
                      })
  end
end
