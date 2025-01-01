# typed: false
# frozen_string_literal: true

class Gists::SessionsController < Gists::ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:create]

  CallbackError = Class.new(StandardError)

  around_action :select_write_database, only: :create
  before_action :validate_oauth_state, only: :create
  skip_before_action :auto_oauth

  # Action: Initiates the OAuth flow by redirecting to
  # GitHub to request an authorization token. Gist is
  # a trusted OAuth application so the user will implicitly
  # accept the authorization without seeing the permissions
  # screen.
  def new
    redirect_to oauth_authorization_url
  end

  # Action: Callback endpoint for the OAuth flow. Since Gist
  # is a trusted GitHub-owned application we're given an internal
  # `browser_session_id` param. With this we are able to lookup the
  # user session record the user is currently using on GitHub.
  #
  # We need access to the user session so that we can add our own
  # Gist specific key to that record. This is the key we'll keep in
  # a cookie to authenticate the user for future requests.
  def create
    handle_oauth_error!
    user_info = fetch_user_info(params[:code])

    if user_session = lookup_user_session(user_info, params[:browser_session_id])
      key, hashed_key = UserSession.random_key_pair
      user_session.update_column :hashed_gist_key, hashed_key
      set_session_cookie(user_session, key, cookie_name: :gist_user_session)

      redirect_to_return_to
    else
      redirect_to_login return_to
    end
  rescue OAuth2::Error => e
    if e.code.to_s == "bad_verification_code" || e.response.status == 401
      # Verification code is invalid or expired.
      # Most likely due to two browser windows racing
      # each other through the OAuth flow.
      # Try the oauth dance again.
      url_options = return_to ? { return_to: return_to } : {}
      redirect_to gist_oauth_login_path(url_options)
    else
      raise
    end
  end

  def destroy
    user_session_cookies_delete
    self.current_user = nil

    redirect_to confirm_logout_url(host: GitHub.host_name)
  end

  private

  def oauth_authorization_url
    callback_options = params.slice(:return_to).permit(:return_to)
    callback_url = gist_oauth_callback_url(callback_options)

    set_oauth_state

    client.auth_code.authorize_url(
      client_id: GitHub.gist_oauth_client_id,
      redirect_uri: callback_url,
      state: cookies[:gist_oauth_csrf],
    )
  end

  def client # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @client ||= OAuth2::Client.new(
      GitHub.gist_oauth_client_id,
      GitHub.gist_oauth_secret_key,
      client_options,
    )
  end

  def client_options
    if ENV["STAFF_ENVIRONMENT"] == "garage" || GitHub.local_host_name_short == "github-staff2-cp1-prd"
      # Gist hosted on gist-garage.github.com
      {
        site: GitHub.api_url,
        authorize_url: "https://garage.github.com/login/oauth/authorize",
        token_url: "#{GitHub.url}/login/oauth/access_token",
        connection_opts: {
          # API on staff boxes requires requests be authenticated with a staff cookie.
          headers: { cookie: "staffonly=#{cookies[:staffonly]}" },
        },
      }
    else
      {
        site: GitHub.api_url,
        authorize_url: "#{GitHub.url}/login/oauth/authorize",
        token_url: "#{GitHub.url}/login/oauth/access_token",
      }
    end
  end

  def gist_oauth_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @app ||= OauthApplication.find_by(key: GitHub.gist_oauth_client_id)
  end

  def handle_oauth_error!
    return unless params[:error]

    raise CallbackError.new
  end

  def fetch_user_info(oauth_code)
    access_token = client.auth_code.get_token(oauth_code,
      client_id: GitHub.gist_oauth_client_id,
      client_secret: GitHub.gist_oauth_secret_key)

    access_token.options[:mode] = :header
    access_token.get("user").parsed
  end

  def lookup_user_session(user_info, oauth_session_secret)
    return unless user = User.find_by(id: user_info["id"])

    user.sessions.active.find do |user_session|
      user_session.valid_for_oauth_application?(gist_oauth_app, oauth_session_secret)
    end
  end

  def redirect_to_return_to
    safe_redirect_to return_to,
      allow_query: true,
      allow_fragment: true,
      allow_hosts: [GitHub.gist3_host_name]
  end

  def return_to # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @return_to ||= session.delete(:return_to) || request.env["return_to"] || params[:return_to]
  end

  def set_oauth_state
    cookies[:gist_oauth_csrf] = SecureRandom.hex(32)
  end

  def validate_oauth_state
    valid =
      cookies[:gist_oauth_csrf].present? &&
      params[:state].present? &&
      SecurityUtils.secure_compare(cookies[:gist_oauth_csrf], params[:state])

    cookies.delete(:gist_oauth_csrf)
    redirect_to_login return_to unless valid
  end
end
