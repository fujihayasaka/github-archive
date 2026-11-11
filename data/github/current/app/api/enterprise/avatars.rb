# typed: true
# frozen_string_literal: true

# Authenticated API proxy to the internal avatar service (alambic).
#
# This takes an authenticated API request and proxies it to the
# unauthenticated internal alambic avatars endpoint. The public avatars
# endpoint on GHES requires a session cookie which makes it impossible
# for API-only clients to load avatars.
#
# See https://github.com/github/github/issues/71916
# See https://github.com/github/alambic/blob/e46e836d6/docs/avatars/README.md#internal-api
class Api::Enterprise::Avatars < Api::App
  before do
    deliver_error! 404 unless GitHub.enterprise?
  end

  # Match all the supported routes in alambic, see:
  #
  # https://github.com/github/alambic/blob/c16302bc96bd34b/avatars/avatars.go#L116-L128
  #
  # With the exception of marketplace avatars (/ml/ and /nml/)
  # since these shouldn't be necessary on GHES.

  get "/enterprise/avatars/u/e", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    deliver_error! 404 unless email = params[:email]
    alambic_proxy("avatars/u/e", email: email)
  end

  get "/enterprise/avatars/u/:user_id", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    user_id = int_id_param!(key: :user_id, halt: true)
    alambic_proxy("avatars/u/#{user_id}")
  end

  get "/enterprise/avatars/:login", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    deliver_error! 422 unless User::LOGIN_REGEX =~ params[:login]
    alambic_proxy("avatars/#{params[:login]}")
  end

  get "/enterprise/avatars/oa/:app_id", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    app_id = int_id_param!(key: :app_id, halt: true)
    alambic_proxy("avatars/oa/#{app_id}")
  end

  get "/enterprise/avatars/in/:integration_id", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    integration_id = int_id_param!(key: :integration_id, halt: true)
    alambic_proxy("avatars/in/#{integration_id}")
  end

  get "/enterprise/avatars/t/:team_id", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    team_id = int_id_param!(key: :team_id, halt: true)
    alambic_proxy("avatars/t/#{team_id}")
  end

  get "/enterprise/avatars/b/:business_id", operation_id: :internal do
    @route_owner = "@github/desktop"
    # cap_bypass:to_fix disabled because it is not passing a resource ref: https://github.com/github/authorization/issues/2239
    control_access :authenticated_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    business_id = int_id_param!(key: :business_id, halt: true)
    alambic_proxy("avatars/b/#{business_id}")
  end

  # Internal: Allows us to override the default adapter in tests.
  # See test/integration/api/enterprise/avatars_test.rb
  def self.configure_faraday(faraday_builder)
    faraday_builder.adapter(Faraday.default_adapter)
  end

  private

  # Makes a request to the alambic avatars endpoint and delivers the raw response
  # from alambic to the user.
  def alambic_proxy(path, request_params = {})
    request_params.update(alambic_params)

    conn = Faraday.new(url: GitHub.alambic_url) do |f|
      self.class.configure_faraday(f)
    end

    conn.headers[:user_agent] = "GHES Alambic Proxy"
    conn.options[:open_timeout] = 1
    conn.options[:timeout] = 1

    alambic_response = conn.get(path, request_params)

    alambic_last_modified = parse_last_modified(alambic_response.headers["Last-Modified"])

    if alambic_response.status != 200 || alambic_response.headers["Content-Type"] !~ /\Aimage\//
      deliver_error! 500
    end

    options = {
      status: alambic_response.status,
      content_type: alambic_response.headers["Content-Type"],
      last_modified: alambic_last_modified,
      etag: alambic_response.headers["ETag"],
    }

    # An hour long TTL is the default for a GHES instance. The actual configured TTL is defined
    # in the `applications.avatars_max_age` config var in GHES and ideally we'd use that but
    # unfortunately we don't have access to it here. It's probably not big deal since it's
    # only our clients that will use this.
    options[:max_age] = 3600

    deliver_raw(alambic_response.body, options)
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError
    deliver_error! 503,
      message: "The Enterprise Avatar API is temporarily unavailable."
  end

  def parse_last_modified(header)
    Time.rfc2822(header)
  rescue ArgumentError
    nil
  end

  # Returns a parameter hash with a copy of the incoming parameter that
  # are known to work with all alambic avatar endpoints. Currently only
  # `s` (size).
  def alambic_params
    { s: params[:s] }.compact
  end
end
