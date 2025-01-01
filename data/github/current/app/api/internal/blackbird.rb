# typed: true
# frozen_string_literal: true

class Api::Internal::Blackbird < Api::Internal
  include ReceiveSchemaWithOpenApi

  REPO_LIMIT = 1_000

  # We have observed the has_readme? method taking over 9 seconds to complete.
  # This causes problems fetching repository metadata because the overall request times out.
  # Instead, we will set a reasonable timeout on this request.
  HAS_README_TIMEOUT_SECS = 1

  before do
    deliver_error!(404) if GitHub.enterprise?
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

    if data["force_new_accessible_resources"]
      accessible_resources
    else
      legacy_accessible_resources
    end
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
  # Requires a JSON body with a `cursor` (string) or `repository_ids` ([int])
  post "/internal/blackbird/repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    ActiveRecord::Base.connected_to(role: :reading) do
      if data["cursor"]
        deliver_error!(400, message: "cursor query param is not supported in this environment") unless GitHub.multi_tenant_enterprise?
        limit = [data["limit"] || REPO_LIMIT, REPO_LIMIT].min

        # TODO: Use domain model to load.
        repos = Repository
          .active
          .order(:id)
          .where("repositories.id >= ?", data["cursor"])
          .limit(limit)
          .all
      else
        repo_ids = data["repository_ids"]
        deliver_error!(400, message: "repository_ids query param is required if cursor query param is not provided") if repo_ids.blank?
        deliver_error!(400, message: "repository_ids exceeds allowed limit (#{REPO_LIMIT})") if repo_ids.length > REPO_LIMIT

        repos = ::Repositories.domain.by_ids(repo_ids)
      end

      # NOTE: We load owners separately so we can load trade restrictions with them to prevent an n+1 query
      owners = Users.domain.by_ids(repos.map(&:owner_id))
      GitHub::PrefillAssociations.prefill_associations(owners, [:trade_controls_restriction])
      GitHub::PrefillAssociations.prefill_associations(repos, [:internal_repository, :repository_auth_version, :network])
      GitHub::PrefillAssociations.prefill_associations(repos, :owner, available_records: owners)

      found_repo_ids = repos.map(&:id)

      # NOTE: There is no association between repositories and CopilotIndexedRepositories, so we cannot prefill assocations
      copilot_indexed_repos = CopilotIndexedRepositories
        .where(repository_id: found_repo_ids)
        .index_by(&:repository_id)

      result = {
        repositories: repos.filter_map { |repo| bulk_repo_hash(repo, copilot_indexed_repos) }
      }

      if data["cursor"]
        # If the number of repositories found (before filtering) is equal to the limit, then we return a next_cursor for the caller
        # to continue paging through the remaining repository records. Otherwise no next_cursor is returned, indicating
        # that the caller has reached the end of the repository records.
        if found_repo_ids.length == limit
          result[:next_cursor] = (T.must(found_repo_ids.last) + 1).to_s
        end
      end

      deliver_raw(result)
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
      deliver_error!(400, message: "property 'request_user_ip' is required in request body")
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
      request_id: request_id,
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

      deliver_error!(401, message: result.failure_reason.to_s)
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
      deliver_error!(400, message: "property 'token' is required in request body")
    end

    @token = GitHub::Authentication::SignedAuthToken::Session.verify(
      token: data["token"],
      scope: scope,
    )

    unless @token.valid?
      if @token.bad_token?
        deliver_error!(401, message: "token format is invalid")
      elsif @token.bad_scope?
        deliver_error!(401, message: "token is not valid within the scope of this page")
      elsif @token.bad_login?
        deliver_error!(401, message: "token has an invalid user id")
      elsif @token.expired?
        deliver_error!(401, message: "token has expired")
      elsif @token.user_suspended?
        deliver_error!(401, message: "token is for a suspended user")
      elsif @token.session_expired?
        deliver_error!(401, message: "token's session has expired")
      elsif @token.session_revoked?
        deliver_error!(401, message: "token's session has been revoked")
      else
        deliver_error!(401, message: "token is malformed or has been tampered with")
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

  def token_kind
    return data["token_kind"] if data["token_kind"] == Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
    Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB
  end

  def accessible_resources
    actor_id = data["actor_id"]
    deliver_error!(400, message: "property 'actor_id' is required in request body") if actor_id.blank?

    key_prefix = data["key_prefix"]
    deliver_error!(400, message: "property 'key_prefix' is required in request body") if key_prefix.blank?

    session_id = data["session_id"]
    deliver_error!(400, message: "property 'session_id' is required in request body") if session_id.blank?

    token = data["token"]
    deliver_error!(400, message: "property 'token' is required in request body") if token.blank?

    auth_result = BlackbirdSearch::AuthenticationAttempt.new(
      request_user_ip: request_user_ip,
      request_id: request_id,
      token: token,
      token_kind: token_kind,
      user_agent: request.user_agent
    ).result

    deliver_error!(401, message: auth_result.error) unless auth_result.success?

    key = BlackbirdSearch::Redis.key(key_prefix: key_prefix, actor_id: actor_id, session_id: session_id)
    cache_entry_result = BlackbirdSearch::Redis.get(key: key)
    if !cache_entry_result.ok?
      GitHub.logger.error("error getting accessible resources cache entry", {
          "exception" => cache_entry_result.error,
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.actor.id" => actor_id,
          "request_id" => request_id,
        })
      deliver_error!(500, message: "unexpected error when fetching accessible resources")
    end

    if cache_entry_result.value!
      ttl_result = BlackbirdSearch::Redis.pttl(key: key)
      if ttl_result.ok?
        remaining_ttl_ms = ttl_result.value!
        if remaining_ttl_ms <= 1.minute.to_i * 1000
          BlackbirdSearch::Redis.with_redis_retry do
            BlackbirdAccessibleResourcesJob.perform_later(
              actor: T.must(auth_result.actor),
              auth_id: T.must(auth_result.auth_id),
              auth_type: auth_result.auth_type,
              expires_at: auth_result.expires_at,
              has_lock: false,
              key_prefix: key_prefix,
              request_id: request_id,
              request_user_ip: request_user_ip,
              session_id: session_id,
              token_kind: token_kind,
            )
          end
        end
      end
      return deliver_raw(Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources.decode(cache_entry_result.value!).to_h)
    end

    # If cache miss for actor's accessible resources:
    #   Attempt to acquire lock.
    #     If lock cannot be acquired, return 202 http status (another process is already refreshing the cache).
    #     If lock is acquired, attempt to build the actor within the specified timeout.
    #       If actor is built, cache the result, release lock, and return the result with 200 http status.
    #       If actor cannot be built (timeout condition) reached, enqueue a background job (has_lock: true) using hash locking, don't release the lock, and return 202 http status.
    mutex = BlackbirdSearch::Redis.mutex(key: key)
    begin
      mutex.lock
      blackbird_actor = T.must(auth_result.blackbird_actor)

      Timeout::timeout(8.seconds) do
        @accessible_resources = blackbird_actor.accessible_resources
      end

      BlackbirdSearch::Redis.set(
        key: key,
        value: @accessible_resources.to_proto,
        expire_sec: 10.minutes,
      )

      mutex.unlock
      deliver_raw(@accessible_resources.to_h)
    rescue GitHub::Redis::Mutex::LockError
      # If lock cannot be acquired another another process is already refreshing the cache, return accepted response.
      deliver_empty({ status: 202 })
    rescue Timeout::Error
      BlackbirdSearch::Redis.with_redis_retry do
        # If computing accessible resources times out, enqueue a background job without releasing the lock, and return accepted response.
        BlackbirdAccessibleResourcesJob.perform_later(
          actor: T.must(auth_result.actor),
          auth_id: T.must(auth_result.auth_id),
          auth_type: auth_result.auth_type,
          expires_at: auth_result.expires_at,
          has_lock: true,
          key_prefix: key_prefix,
          request_id: request_id,
          request_user_ip: request_user_ip,
          session_id: session_id,
          token_kind: token_kind,
        )
      end

      deliver_empty({ status: 202 })
    rescue => e
      mutex.unlock
      GitHub.logger.error("unexpected error when computing accessible resources", {
        "exception" => e,
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.actor.id" => actor_id,
        "request_id" => request_id,
      })
      deliver_error!(500, message: "unexpected error when computing accessible resources")
    end
  end

  def legacy_accessible_resources
    auth_actor = if data["token_kind"] == Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
      api_auth = auth_for_api
      ::BlackbirdSearch::ApiActor::new(actor: api_auth.user, remote_ip: request_user_ip)
    else
      token = token_for_scope(scope: Search::Blackbird::TOKEN_SCOPE)
      ::BlackbirdSearch::WebActor::new(actor: token.user, session: token.session, remote_ip: request_user_ip)
    end

    if auth_actor.actor.feature_enabled?(:blackbird_background_job_enqueue)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        request_user_ip: request_user_ip,
        request_id: request_id,
        token: data["token"],
        token_kind: token_kind,
        user_agent: request.user_agent
      ).result

      if auth_result.success?
        GitHub.dogstats.increment("blackbird.authentication_attempt", tags: ["success:true", "auth_type:#{auth_result.auth_type}"])
        BlackbirdSearch::Redis.with_redis_retry do
          BlackbirdAccessibleResourcesJob.perform_later(
            actor: T.must(auth_result.actor),
            auth_id: T.must(auth_result.auth_id),
            auth_type: auth_result.auth_type,
            expires_at: auth_result.expires_at,
            has_lock: false,
            key_prefix: data["key_prefix"],
            request_id: request_id,
            request_user_ip: request_user_ip,
            session_id: data["session_id"],
            token_kind: token_kind,
          )
        end
      else
        GitHub.dogstats.increment("blackbird.authentication_attempt", tags: ["success:false", "auth_type:#{auth_result.auth_type}"])
        GitHub.logger.error("blackbird authentication attempt failed", {
          "gh.blackbird_authentication_attempt.error" => auth_result.error,
          "gh.auth_id" => auth_result.auth_id,
          "gh.auth_type" => auth_result.auth_type.to_s,
        })
      end
    end

    deliver_raw(
      {
        accessible_repository_ids: auth_actor.accessible_repository_ids,
        authorized_organization_ids: auth_actor.authorized_organization_ids,
        protected_organization_ids: auth_actor.protected_organization_ids,
        outside_collaborator_owner_ids: auth_actor.outside_collaborator_owner_ids,
      }
    )
  end

  sig do
    params(repo: ::Repositories::IRepository, copilot_indexed_repos: T::Hash[Integer, CopilotIndexedRepositories]).
    returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def bulk_repo_hash(repo, copilot_indexed_repos)
    # Return nil for repositories that are not accessible with checks from ensure_repo_is_accessible.
    #
    # NOTE: Must downcast because IRepository doesn't have all the methods needed for these checks.
    repo = T.cast(repo, Repository) # rubocop:todo GitHub/AvoidCast
    begin
      return nil if repo.network_broken? # Broken network (raises NetworkMissingError if database is in an invalid state)
      return nil if repo.access.disabled? # DMCA takedowns, etc
      return nil if repo.disabled? # Trade restrictions
      return nil if repo.owner.nil? # Orphaned repo
    rescue Repository::NetworkDependency::NetworkMissingError => e
      Failbot.report e
      return nil
    end

    {
      id: repo.id,
      name: repo.name,
      owner_id: T.must(repo.owner).id,
      owner_login: T.must(repo.owner).login,
      public: repo.public?,
      archived: repo.archived?,
      updated_at: Api::Serializer::time(repo.updated_at),
      experiments: Search::Blackbird.experiments(copilot_indexed_repos[T.must(repo.id)]),
      seq_no: repo.repository_auth_version&.version || 1,
    }
  end
end
