# typed: true
# frozen_string_literal: true

class Api::Limiters::TwirpElapsedTimeByClient < GitHub::Limiters::MemcachedWindow
  include Api::Limiters::TwirpHelpers

  TWIRP_CLIENT_CUSTOM_MULTIPLIERS = {
    # high-volume clients
    "launch" => 8,
    "package_registry" => 8,
    # bursty
    "turboghas" => 4,
    "octoshift" => 4,
    "token_scanning_service" => 2,
    "education_web" => 2,
  }

  attr_reader :max

  def initialize(max:)
    @max = max
    super("twirp-elapsed-time-by-client", limit: max)
  end

  def start(request)
    if self.class.twirp_elapsed_time_by_client_vnext_enabled?(request)
      set_custom_limit(request)
      super(request)
    else
      OK
    end
  end

  def record_finish(request)
    if self.class.twirp_elapsed_time_by_client_vnext_enabled?(request)
      increment_counter(request)

      if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
        log_data["gh.api.twirp.client_name"] = twirp_client_name_per_request(request)
        log_data["gh.api.twirp.elapsed.cost"] = cost(request)
        log_data["gh.api.twirp.elapsed.current"] = val(key(request))
        log_data["gh.api.twirp.elapsed.max"] = @limit
      end
    else
      OK
    end
  end

  # If the request was canceled we don't want to cost the request.
  def cancel(request)
    OK
  end

  protected

  def set_custom_limit(request)
    client_name = twirp_client_name_per_request(request)

    multiplier = TWIRP_CLIENT_CUSTOM_MULTIPLIERS[client_name] || 1
    @limit = @max * multiplier
  end

  # Protected: The key is composed of the client name, request ip.
  def key(request)
    client_name = twirp_client_name_per_request(request)
    "#{client_name}::#{request.ip}"
  end

  def twirp_client_name_per_request(request)
    return request.env[:twirp_client_name] if request.env[:twirp_client_name].present?

    request.env[:twirp_client_name] = twirp_client_name_no_memoization(request)
  end

  def twirp_client_name_no_memoization(request)
    self.class.twirp_client_name(request) || Api::Limiters::TwirpAuthenticationFingerprintByPath::UNKNOWN_CLIENT_NAME
  end

  def cost(request)
    cost = request.env[Api::Limiters::ElapsedTimeByAuthenticationFingerprint::REQUEST_COST_KEY]

    return cost if cost.present?

    # The cost should be the number of milliseconds this request has taken
    cost = Integer((Time.now - T.cast(request.env[Api::Limiters::ElapsedTimeByAuthenticationFingerprint::REQUEST_STARTED_AT], Time)) * 1_000)

    request.env[Api::Limiters::ElapsedTimeByAuthenticationFingerprint::REQUEST_COST_KEY] = cost
  end
end
