# typed: false
# frozen_string_literal: true

# API endpoints for internal apps.  Each app requires a specific media type
# to function.
#
# https://github.com/github/ce-engineering/blob/master/docs/api/Internal-API.md
#
class Api::Internal < Api::App
  CONTENT_HMAC_KEY = "HTTP_CONTENT_HMAC"
  REQUEST_METHOD = "REQUEST_METHOD"
  PATH_INFO = "PATH_INFO"
  SKIP_HMAC = Set.new(%w(GET HEAD OPTIONS))
  BAD_HMAC_STATUSES = Set.new([:fail, :empty])

  # Regex pattern matching internal services
  PATH_REGEX = /\A(?:\/api)?\/internal/i.freeze

  rate_limit_as nil

  class MissingContentHMAC < StandardError; end
  class ExternalIPRequest < StandardError; end

  class << self
    attr_accessor :required_api_semantic_version
  end

  def self.content_hmac(body, hmac = GitHub.internal_api_hmac_keys.first.to_s)
    mac = OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, hmac, body)
    "#{HMAC_ALGORITHM} #{mac}"
  end

  def self.verify_content_hmac(env, body)
    method = env[REQUEST_METHOD]
    return :skip_method if SKIP_HMAC.include?(method)

    has_hmac = GitHub.internal_api_hmac_keys.present?
    expected_mac = env[CONTENT_HMAC_KEY]

    return :skip if !has_hmac && expected_mac.blank?

    status = if has_hmac

      if expected_matches_internal?(expected_mac, body)
        :success
      elsif expected_mac.blank?
        err = MissingContentHMAC.new "No Content-HMAC on #{method} #{env[PATH_INFO]}"
        Failbot.report_user_error(err)

        :empty
      else
        :fail
      end
    else
      :no_key
    end

    status
  ensure
    GitHub.dogstats.increment("api.internal.hmac", tags: ["status:#{status}"])
  end

  def self.expected_matches_internal?(expected_mac, body)
    GitHub.internal_api_hmac_keys.each do |key|
      if SecurityUtils.secure_compare(expected_mac.to_s, content_hmac(body, key))
        return true
      end
    end

    false
  end

  def self.api_stats_key
    @api_stats_key ||= name.demodulize.underscore
  end

  before do
    verify_internal_request
    require_internal_semantic_version
    verify_request_hmac
  end

  def self.require_api_semantic_version(v)
    Api::MediaType::SemanticVersions << v
    self.required_api_semantic_version = v
  end

  def require_internal_semantic_version
    return unless v = self.class.required_api_semantic_version
    require_api_semantic_version(v)
  end

  def verify_and_receive(expected_type, required: true)
    json = request.body.read

    hmac_status = Api::Internal.verify_content_hmac(env, json)
    if BAD_HMAC_STATUSES.include?(hmac_status)
      deliver_error! 403, message: CONTENT_HMAC_MISMATCH
    end

    receive_json(json, type: expected_type, required: required)
  end

  def verify_request_hmac
    # While we transition internal APIs we only check the HMAC if one is set OR
    # the API has opted in to requiring a request HMAC.
    return unless env[REQUEST_HMAC_HEADER].present? || require_request_hmac?

    unless hmac_authenticated_internal_service_request?
      deliver_error! 403, message: REQUEST_HMAC_INVALID
    end
  end

  # used to override `from` metric tag in app/platform/authorization.rb:api_auth and
  # lib/github/authentication/attempt.rb:instrument()
  def source
    :internal_api
  end

  # We are raising ExternalIPRequest exceptions below to enumerate any internal
  # APIs that are called from unknown external addresses. However, we know of a
  # small set of APIs that are called from external addresses. To minimize
  # needle noise, we allowlist these APIs. This is a temporary approach only
  # while we collect needle data.
  KNOWN_EXTERNAL_REQUEST_APIS = [
    Api::Internal::PorterCallbacks,
    Api::Internal::Raw,
    Api::Internal::Archive,
    Api::Internal::Codespaces::Webhook,
    Api::Internal::Codespaces::Prebuilds,
    Api::Internal::Codespaces::PortForwarding,
    Api::Internal::Codespaces::Failover,
    Api::Internal::GitHubModels::Access,
    Api::Internal::Apps,
    Api::Internal::ActionsImageDeployment,
    Api::Internal::EntraUserLicensedForGhe,
    Api::Internal::ImmutableActions,
  ].freeze
  # This is a belt and suspenders check to ensure that internal APIs, by
  # default, are only accessed from within our own infrastructure.
  #
  # ****************************************************************************
  # This is NOT meant to be the sole line of defense for protecting internal
  # APIs. All internal APIs should also require a HMAC between client and
  # server. Long-term, we would ideally split the "fully internal" APIs into a
  # standalone app that isn't even routable externally.
  # ****************************************************************************
  #
  def verify_internal_request
    # We don't control and/or can't trust the IP space in some environments.
    return unless GitHub.remote_ip_restrictions_enabled?

    internal_request = internal_ip_request?

    # We aren't sure if any internal API requests are actually coming from
    # external sources today. For now, all internal APIs default to
    # `externally_accessible?` returning `true`. Once we collect data to ensure
    # we won't break any callers, we will switch `externally_accessible?` to
    # return `false` by default. The hope is we can block all external callers
    # or dramtically reduce the number of internal APIs that override
    # `externally_accessible?` to return true.
    unless internal_request || KNOWN_EXTERNAL_REQUEST_APIS.include?(self.class)
      err = ExternalIPRequest.new "Internal only API requested from an external IP for #{self.class}"
      Failbot.report_trace(err)
    end

    # We don't care if this is an internal request if the API has opted into
    # being externally accessible.
    return if externally_accessible?

    # To avoid leaking any existence of a private internal endpoint we 404
    # instead of 403.
    #
    # Drop `dynamic_lab?` from this clause once
    # https://github.com/github/github/issues/94648 is resolved.
    deliver_error! 404 if !internal_request || GitHub.dynamic_lab?
  end

  # While we assess internal APIs we default all of them to being externally
  # accessible (as they were before we started locking things down more
  # strictly). But, as we assess each internal API, we can opt in specific
  # endpoints to require all clients are from internal hosts. Once we are
  # confident, we can default this to `false` and require specific internal APIs
  # to override it to `true`.
  def externally_accessible?
    true
  end

  # We allow private mode access only if we can establish some form of trust with the caller. That can take multiple
  # forms:
  #  - Public API auth
  #  - HMAC auth
  # Anonymous internal API access is not allowed.
  def authenticated_for_private_mode?
    super || require_request_hmac?
  end

  def record_stats
    super
    ms = (Time.now - @request_start_time) * 1000
    @api_stats_key ||= self.class.api_stats_key
    # covered in datadog by request.by_controller.time with tag:
    # "controller:api/internal/foo"
    GitHub.dogstats.timing(@api_stats_key, ms, tags: ["via:api", "visibility:internal"])
  end

  def find_repo
    ActiveRecord::Base.connected_to(role: :reading) { super }
  end

  def find_user
    ActiveRecord::Base.connected_to(role: :reading) { super }
  end

  def find_org
    ActiveRecord::Base.connected_to(role: :reading) { super }
  end

  def deliver(*args)
    ActiveRecord::Base.connected_to(role: :reading) { super }
  end
end
