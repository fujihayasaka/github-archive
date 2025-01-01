# typed: false
# frozen_string_literal: true

Mime::Type.register "application/ocsp-request", :ocsp_request

module GitHub::OCSP
  OK      = "ok"
  REVOKED = "revoked"
  ERROR   = "error"
  PENDING = "pending"

  # Use OCSP to check if any certificates in a chain have been revoked.
  #
  # chain - An Array of OpenSSL::X509::Certificate instances.
  #
  # Returns OK, REVOKED, ERROR, or PENDING.
  def check_async(chain)
    Failbot.push(app: GitSigning::FAILBOT_APP, "gh.ocsp.certificate.chain": chain)

    checks = checks_for_chain(chain)
    return OK if checks.empty?

    keys = checks.map { |c| cache_key(c) }
    results = Repositories::Kv.store.mget(keys).value do |err|
      Failbot.report(err)
      return ERROR
    end

    return REVOKED if results.include?(REVOKED)
    return ERROR   if results.include?(ERROR)
    return OK      if results.all? { |r| r == OK }

    results.zip(checks).each { |r, c| enqueue(c) if r.nil? }

    PENDING
  rescue GitSigning::OCSPError, OpenSSL::ASN1::ASN1Error => e
    Failbot.report(e)
    ERROR
  ensure
    Failbot.pop
  end

  # Use OCSP to check if any certificates in a chain have been revoked.
  #
  # subject   - An OpenSSL::X509::Certificate instance.
  # issuer    - An OpenSSL::X509::Certificate instance.
  # untrusted - An Array of OpenSSL::X509::Certificate instances.
  #
  # Returns OK, REVOKED, ERROR, or PENDING.
  def check_sync(subject, issuer, untrusted)
    Failbot.push(
      app: GitSigning::FAILBOT_APP,
      "gh.ocsp.certificate.subject": subject,
      "gh.ocsp.certificate.issuer": issuer,
      "gh.ocsp.certificate.untrusted": untrusted,
    )

    check = Check.new(subject, issuer, untrusted)

    begin
      check.perform
    rescue GitSigning::OCSPError, Faraday::Error, OpenSSL::ASN1::ASN1Error => e
      Failbot.report(e)
    ensure
      Repositories::Kv.store.set(cache_key(check), check.state, expires: check.next_update)
    end

    check.state
  ensure
    Failbot.pop
  end

  # Get Checks for each subject/issuer pair in a certificate chain.
  #
  # chain - An Array or OpenSSL::X509::Certificate instances.
  #
  # Returns an Array of Checks.
  def checks_for_chain(chain)
    return [] if chain.length < 2

    subjects = chain[0..-2]
    issuers  = chain[1..-1]
    checks   = subjects.zip(issuers).map do |subject, issuer|
      Check.new(subject, issuer, chain - [subject, issuer])
    end

    # Ignore certificates that don't have an OCSP URI.
    checks.reject! { |check| check.uri.nil? }

    checks
  end

  # Cache key for storing a check's result in KV.
  #
  # Returns a String.
  def cache_key(check)
    # The certificate id makes for a good cache key, as it is meant to be a
    # globaly unique identifier of the subject certificate.
    cert_id = check.certificate_id(OpenSSL::Digest::SHA256.new)
    hexdigest = OpenSSL::Digest::SHA256.hexdigest(cert_id.to_der)

    "ocsp-check.#{hexdigest}"
  end

  # Enqueue a job to make an OCSP request.
  #
  # Returns nothing.
  def enqueue(check)
    b64_subject = Base64.strict_encode64(check.subject.to_der)
    b64_issuer  = Base64.strict_encode64(check.issuer.to_der)
    b64_untrusted = check.untrusted.map { |u| Base64.strict_encode64(u.to_der) }
    FetchOcspJob.perform_later(b64_subject, b64_issuer, *b64_untrusted)
  end

  class Check
    # Don't reject responses whose this_update is 30 seconds in the future or
    # whose next_update is 30 seconds in the past.
    ALLOWED_CLOCK_SKEW = 30.seconds

    attr_reader :subject, :issuer, :untrusted, :state, :next_update

    # Initialize a new OCSP::Check.
    #
    # subject   - An OpenSSL::X509::Certificate instance.
    # issuer    - An OpenSSL::X509::Certificate instance. The issuer of subject.
    # untrusted - An Array of OpenSSL::X509::Certificate instances to use during
    #             chain building.
    #
    # Returns nothing.
    def initialize(subject, issuer, untrusted)
      @subject = subject
      @issuer = issuer
      @untrusted = untrusted
    end

    def perform
      @state = GitHub::OCSP::ERROR
      @next_update = 12.hours.from_now

      single = single_response
      if single.nil?
        raise GitSigning::OCSPError, "Missing status for certificate"
      end

      this_update = single.this_update
      next_update = single.next_update
      if this_update && this_update > ALLOWED_CLOCK_SKEW.from_now
        raise GitSigning::OCSPError, "this_update in future: #{this_update}"
      elsif next_update && next_update < ALLOWED_CLOCK_SKEW.ago
        raise GitSigning::OCSPError, "next_update in past: #{next_update}"
      elsif this_update && next_update && this_update > next_update
        raise GitSigning::OCSPError, "next_update before this_update"
      elsif next_update.nil? || next_update < 6.hours.from_now
        next_update = 6.hours.from_now # don't check again too often
      end

      case single.cert_status
      when OpenSSL::OCSP::V_CERTSTATUS_GOOD
        @state = GitHub::OCSP::OK
        @next_update = next_update
      when OpenSSL::OCSP::V_CERTSTATUS_REVOKED
        @state = GitHub::OCSP::REVOKED
        @next_update = nil
      else
        raise GitSigning::OCSPError, "bad cert status: '#{single.cert_status}'"
      end
    end

    # Search the OCSP basic response for the status of our subject certificate.
    #
    # The OpenSSL::OCSP::BasicResponse#status doccumentation describes the
    # return value:
    #   ... contains a CertificateId, the status (0 for good, 1 for
    #   revoked, 2 for unknown), the reason for the status, the revocation time,
    #   the time of this update, the time for the next update and a list of
    #   OpenSSL::X509::Extensions.
    #
    # http://ruby-doc.org/stdlib-2.3.0/libdoc/openssl/rdoc/OpenSSL/OCSP/BasicResponse.html#method-i-status
    #
    # Returns an OpenSSL::OCSP::SingleResponse instance.
    def single_response
      basic = basic_response

      if basic.nil?
        raise GitSigning::OCSPError, "unknown OCSP response type"
      end

      unless basic.verify(untrusted + [issuer], GitHub.git_signing_smime_cert_store)
        raise GitSigning::OCSPError, "invalid OCSP response signature"
      end

      case res = ocsp_request.check_nonce(basic)
      when -1 # nonce in request only
      when  1 # nonces equal
      else
        raise GitSigning::OCSPError, "nonce check failed with code #{res}"
      end

      basic.responses.find do |other|
        # Their response might have caluclated the certificate ID using a
        # different digest, so we have to recalculate ours.
        this = certificate_id(OpenSSL::Digest.new(other.certid.hash_algorithm))
        other.certid.cmp(this)
      end
    end

    # The OCSP "basic" response from issuing the OCSP request.
    #
    # Returns a OpenSSL::OCSP::BasicResponse instance.
    def basic_response
      resp = ocsp_response

      unless resp.status == OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL
        raise GitSigning::OCSPError, "bad OCSP response status: #{resp.status}"
      end

      resp.basic
    end

    # The OCSP response from issuing the OCSP request.
    #
    # Returns a OpenSSL::OCSP::Response instance.
    def ocsp_response
      resp = http_response

      unless resp.success?
        raise GitSigning::OCSPError, "bad OCSP response status: #{resp.status}"
      end

      OpenSSL::OCSP::Response.new(resp.body)
    end

    # The HTTP response from issuing the OCSP request.
    #
    # Returns a Faraday::Response instance.
    def http_response
      if uri.nil?
        raise GitSigning::OCSPError, "No OCSP URI"
      end

      proxy_host = URI.parse(uri).find_proxy(
        "http_proxy"  => GitHub.http_proxy_config,
        "https_proxy" => GitHub.http_proxy_config,
        "no_proxy"    => GitHub.no_proxy_config,
      )

      # TODO: how do we prevent requests to local network? This isn't a huge
      # concern yet, since we're only dealing with URLs specified by actual
      # public CAs.
      Faraday.post(uri) do |http_request|
        unless proxy_host.nil?
          http_request.options.proxy = Faraday::ProxyOptions.from(proxy_host)
        end

        http_request.options.timeout = 5.seconds
        http_request.body = ocsp_request.to_der
        http_request.headers["Content-Type"] = Mime[:ocsp_request].to_s
      end
    end

    # An OCSP request for validating the subject certificate.
    #
    # Returns a OpenSSL::OCSP::Request instance.
    def ocsp_request
      @ocsp_request ||= OpenSSL::OCSP::Request.new.tap do |req|
        digest = GitHub.fips_mode? ? OpenSSL::Digest::SHA256.new : OpenSSL::Digest::SHA1.new # rubocop:disable GitHub/InsecureHashAlgorithm
        req.add_certid(certificate_id(digest))
        req.add_nonce
      end
    end

    # A unique identifier for the subject certificate.
    #
    # digest - An OpenSSL::Digest instance.
    #
    # Returns a OpenSSL::OCSP::CertificateId instance.
    def certificate_id(digest)
      OpenSSL::OCSP::CertificateId.new(@subject, @issuer, digest)
    end

    # The URI of the OCSP responder.
    #
    # Returns a String URI or nil. Raises GitSigning::OCSPError or
    # OpenSSL::ASN1::ASN1Error.
    def uri
      return @uri if defined?(@uri)
      @uri = parse_uri
    end

    def parse_uri
      @subject.extensions.each do |ext|
        # The OpenSSL::X509::Extension objects returned from
        # Certificate#extensions aren't very convenient to work, so we reparse the
        # extension to get the ASN1 data structures.
        ext_asn1 = OpenSSL::ASN1.decode(ext.to_der)

        # ASN.1 profile for X.509 extensions can be found in
        # https://tools.ietf.org/html/rfc5280#section-4.1
        unless ext_asn1.tag == OpenSSL::ASN1::SEQUENCE && [2, 3].include?(ext_asn1.value.length)
          raise GitSigning::OCSPError, "invalid x.509 extension"
        end

        # Looking for Authority Information Access extension.
        ext_oid, ext_value = ext_asn1.value.first, ext_asn1.value.last
        next unless ext_oid.sn == "authorityInfoAccess"

        # Extension value is a DER encoded OCTET STRING. The ASN.1 profile for
        # Authority Information Access extension can be found in
        # https://www.ietf.org/rfc/rfc2459.txt section 4.2.2.1.
        access_descriptions = OpenSSL::ASN1.decode(ext_value.value)

        unless access_descriptions.tag == OpenSSL::ASN1::SEQUENCE
          raise GitSigning::OCSPError, "invalid authorityInfoAccess extension"
        end

        # Looking for OCSP access description.
        access_descriptions.value.each do |access_description|
          unless access_description.tag == OpenSSL::ASN1::SEQUENCE && access_description.value.length == 2
            raise GitSigning::OCSPError, "invalid access description"
          end

          access_method_oid, access_location = access_description.value
          next unless access_method_oid.sn == "OCSP"

          # tag == 6 means that this is a URI as per
          # https://www.ietf.org/rfc/rfc2459.txt section A.2.
          next unless access_location.tag == 6

          # Found it!
          return access_location.value
        end
      end

      nil
    end
  end

  extend self
end
