# typed: true
# frozen_string_literal: true

class Api::Internal::Blackbird < Api::Internal
  include ReceiveSchemaWithOpenApi

  @auth_result = T.let(nil, T.nilable(GitHub::Authentication::Result))
  @token = T.let(nil, T.nilable(GitHub::Authentication::SignedAuthToken))

  REPO_LIMIT = 10_000

  # We have observed the has_readme? method taking over 9 seconds to complete.
  # This causes problems fetching repository metadata because the overall request times out.
  # Instead, we will set a reasonable timeout on this request.
  HAS_README_TIMEOUT_SECS = 1

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # List all accessible resources for the token's user & session. This endpoint
  # allows blackbird to appropriately filter search results to the user's
  # accessible repositories.
  #
  # Supports authentication via token using the `token` field if `token_kind`
  # is set to `API`. In the token authentication mode, access control scopes for
  # the token are respected when determining accessible resources.
  #
  # Returns:
  #   - accessible_repository_ids: private repos to which the user (or token) has
  #     read access.
  #   - authorized_organization_ids: organizations to which the user (or token) is
  #     a member of and meets all Conditional Access Policies
  #   - protected_organization_ids: organizations to which the user+session is a
  #     member of but does NOT meet Conditional Access Policies.
  post "/internal/blackbird/accessible_resources", operation_id: "blackbird/list-accessible-resources", exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"
    if data["token_kind"] == Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
      api_auth = auth_for_api
      actor = ::BlackbirdSearch::ApiActor::new(auth_result: api_auth, remote_ip: request_user_ip)
    else
      token = token_for_scope(scope: "Blackbird::AccessToken")
      actor = ::BlackbirdSearch::WebActor::new(access_token: token, remote_ip: request_user_ip)
    end

    outside_collaborator_owner_ids = actor.outside_collaborator_owner_ids
    authorized_organization_ids = actor.authorized_organization_ids
    protected_organization_ids = actor.protected_organization_ids

    deliver_raw(
      {
        accessible_repository_ids: actor.accessible_repository_ids,
        authorized_organization_ids: authorized_organization_ids,
        protected_organization_ids: protected_organization_ids,
        outside_collaborator_owner_ids: outside_collaborator_owner_ids,
      },
    )
  end

  # Get a single repository by id or NWO (using API routing). The response is designed to allow blackbird to keep its
  # repository database in sync with github.
  get "/internal/blackbird/repositories/:repository_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repo do
    @route_owner = "@github/blackbird"
    if repo = find_repo!
      ensure_repo_is_accessible
    end

    if repo.owner.nil?
      deliver_error!(missing_repository_status_code)
    end

    if params[:min_updated_at_ts].present?
      min_updated_at = Time.zone.at(params[:min_updated_at_ts].to_i)

      if repo.updated_at < min_updated_at
        GitHub.logger.info(
          "database replication behind min_updated_at_ts",
          "gh.repo.id" => repo.id,
          "gh.repo.min.updated_at" => min_updated_at,
          "gh.repo.updated_at" => repo.updated_at.to_i
        )
        headers["Retry-After"] = 0.5
        deliver_error!(503, message: "database replication not ready, retry later")
      end
    end

    has_readme = T.let(nil, T.nilable(T::Boolean))
    if GitHub.flipper[:blackbird_readme].enabled?
      start = Time.now
      begin
        GitHub::Timer.timeout(HAS_README_TIMEOUT_SECS) do
          has_readme = repo.has_readme?
          GitHub.dogstats.distribution("blackbird_api.get_repository.has_readme.duration", (Time.now - start) * 1000, tags: ["status:success"])
        end
      rescue GitRPC::Failure, GitRPC::Error, ::Timeout::Error => e
        # NOTE: Having a readme is used only for repository scoring. If the request fails for any reason, continue.
        GitHub.logger.error(
          "error fetching readme, ignoring",
          :exception => e,
          "gh.repo.id" => repo.id)
        GitHub.dogstats.distribution("blackbird_api.get_repository.has_readme.duration", (Time.now - start) * 1000, tags: ["status:error"])
      end
    end

    repo_hash = {
      id: repo.id,
      network_id: repo.network_id,
      owner_id: repo.owner.id,
      owner_login: repo.owner.login,
      owner_spammy: repo.owner.spammy?,
      name: repo.name,
      public: repo.public?,
      archived: repo.archived?,
      disk_usage: repo.disk_usage,
      pushed_at: Api::Serializer.time(repo.pushed_at),
      created_at: Api::Serializer.time(repo.created_at),
      license_name: repo.license&.name,
      num_watchers: repo.watchers_count,
      num_stars: repo.stargazer_count,
      has_readme: has_readme,
      public_fork_count: repo.public_fork_count,
      paying_customer: ::BlackbirdSearch::Helpers.repository_owner_is_paying_customer?(repo),
      fork: repo.fork?,
      experiments: Search::Blackbird.experiments(CopilotIndexedRepositories.find_by(repository_id: repo.id)),
      updated_at: Api::Serializer::time(repo.updated_at),
      seq_no: repo.blackbird_seq_no,
    }

    deliver_raw(repo_hash)
  end

  # Looks up the specified fields for every repository in the provided list of repository ids,
  # or uses a cursor to paginate through all repositories (only in proxima envs).
  # Requires a JSON body with a `cursor` (string) or `repository_ids` ([int]), and `repository_fields` [string] keys.
  post "/internal/blackbird/repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    ActiveRecord::Base.connected_to(role: :reading) do
      sanitized_fields = data["repository_fields"]&.select { |field| Repository.column_names.include?(field) }
      deliver_error!(400, message: "repository_fields has no valid fields") if sanitized_fields.blank?

      if data["cursor"]
        deliver_error!(400, message: "cursor query param is not supported in this environment") unless GitHub.multi_tenant_enterprise?
        limit = [data["limit"] || REPO_LIMIT, REPO_LIMIT].min

        repos = Repository.
          where("repositories.id >= ?", data["cursor"]).
          includes(:repository_auth_version).
          order(:id).
          limit(limit)
        copilot_indexed_repos = CopilotIndexedRepositories
          .where(repository_id: repos.pluck(:id))
          .index_by(&:repository_id)
        result = { repositories: repos.
          pluck(sanitized_fields + ["version"]). # `version` is the column name for the value mapped as seq_no.
          map do |repo|
            (sanitized_fields + ["seq_no"]).zip(repo).to_h.tap do |h|
              h["seq_no"] ||= 1
              h["experiments"] = Search::Blackbird.experiments(copilot_indexed_repos[h["id"]])
            end
          end
        }

        # If the number of repositories returned is equal to the limit, then we return a next_cursor for the caller
        # to continue paging through the remaining repository records. Otherwise no next_cursor is returned, indicating
        # that the caller has reached the end of the repository records.
        if result[:repositories].length == limit
          result[:next_cursor] = (result[:repositories].last["id"] + 1).to_s
        end

        deliver_raw(result)
      else
        repo_ids = data["repository_ids"]
        deliver_error!(400, message: "repository_ids query param is required if cursor query param is not provided") if repo_ids.blank?
        deliver_error!(400, message: "repository_ids exceeds allowed limit (#{REPO_LIMIT})") if repo_ids.length > REPO_LIMIT

        copilot_indexed_repos = CopilotIndexedRepositories
          .where(repository_id: repo_ids)
          .index_by(&:repository_id)
        repos = Repository.
          where(id: repo_ids).
          includes(:repository_auth_version).
          pluck(sanitized_fields + ["version"]). # `version` is the column name for the value mapped as seq_no.
          map do |repo|
            (sanitized_fields + ["seq_no"]).zip(repo).to_h.tap do |h|
              h["experiments"] = Search::Blackbird.experiments(copilot_indexed_repos[h["id"]])
              h["seq_no"] ||= 1
            end
          end

        deliver_raw({
          repositories: repos,
        })
      end
    end
  end

  # Get a single user by id or login (using API routing).
  get "/internal/blackbird/user/:user_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_user do
    @route_owner = "@github/blackbird"
    user = find_user!
    deliver(
      :user_hash,
      user,
      last_modified: calc_last_modified_for_object(user),
      exclude_email: true,
    )
  end

  def require_request_hmac?
    true
  end

  def externally_accessible?
    false
  end

  def check_allowlist_for_request_limiting
    GitHub::Limiters::Middleware.skip_limit_checks(env)
  end

  def resolve_tenant_from_repo
    repo = find_repo!
    Business.find_by(id: repo.tenant_id)
  end

  def resolve_tenant_from_user
    user = find_user!
    Business.find_by(id: user.business_id)
  end

  private

  def request_user_ip
    return @request_user_ip if defined? @request_user_ip

    if data["request_user_ip"].blank?
      deliver_error! 400, message: "property 'request_user_ip' is required in request body"
    end

    @request_user_ip = data["request_user_ip"]
  end

  # Private: Verify a token in the request body from an API request.
  #
  # Returns a GitHub::Authentication::Attempt or delivers an http error
  sig { returns(GitHub::Authentication::Result) }
  def auth_for_api
    return @auth_result if defined? @auth_result

    result = GitHub::Authentication::Attempt.new(
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      from: :blackbird,
      # we can omit these because Blackbird is (for now?) only for dotcom
      # login: request_credentials.login,
      # password: request_credentials.password,
      # otp: request_credentials.otp,
      token: data["token"],
      ip: request_user_ip,
      user_agent: request.user_agent,
      request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
      password_auth_blocked: true,
      url: Rack::RequestLogger.url_for_logging(request.url),
    ).result
    if result.failure?
      # Check if the authentication is valid for an enterprise integration
      headers = {}
      headers["HTTP_AUTHORIZATION"] = "Bearer #{data["token"]}"
      assertion = Api::IntegrationAssertion.new(headers)
      if assertion.valid?
        @auth_result = GitHub::Authentication::Result.success(assertion.integration.bot)
        return @auth_result
      end

      deliver_error! 401, message: result.failure_reason.to_s
    end
    @auth_result = result
  end

  # Private: Verify a token in the request body for the given scope.
  #
  # scope - String scope to verify. Expected to be either
  #         "Blackbird::ExchangeToken" or "Blackbird::AccessToken"
  #
  # Returns a SignedAuthToken or delivers an http error
  sig { params(scope: String).returns(GitHub::Authentication::SignedAuthToken) }
  def token_for_scope(scope:)
    return @token if defined? @token

    if data["token"].blank?
      deliver_error! 400, message: "property 'token' is required in request body"
    end

    @token = GitHub::Authentication::SignedAuthToken::Session.verify(
      token: data["token"],
      scope: scope,
    )

    unless @token.valid?
      if @token.bad_token?
        deliver_error! 401, message: "token format is invalid"
      elsif @token.bad_scope?
        deliver_error! 401, message: "token is not valid within the scope of this page"
      elsif @token.bad_login?
        deliver_error! 401, message: "token has an invalid user id"
      elsif @token.expired?
        deliver_error! 401, message: "token has expired"
      elsif @token.user_suspended?
        deliver_error! 401, message: "token is for a suspended user"
      elsif @token.session_expired?
        deliver_error! 401, message: "token's session has expired"
      elsif @token.session_revoked?
        deliver_error! 401, message: "token's session has been revoked"
      else
        deliver_error! 401, message: "token is malformed or has been tampered with"
      end
    end

    @token
  end

  def data
    return @data if defined? @data
    @data = receive_with_openapi
  end

  def deliver_error!(status, options = {})
    GitHub.logger.error(
      "Internal Blackbird Error",
      "gh.auth.token.error.message" => options[:message],
      "http.status_code" => status
    )
    super(status, options)
  end
end
