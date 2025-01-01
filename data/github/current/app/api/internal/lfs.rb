# typed: true
# frozen_string_literal: true

# Internal Auth endpoint for github/lfs-server
class Api::Internal::Lfs < Api::Internal
  LFS_VERIFY_BATCH_SIZE         = 1000
  LFS_URL_GENERATION_BATCH_SIZE = 1000

  NON_401_ROUTES = [
    "/internal/lfs/download-urls"
  ]
  # Override default blanket 404 to 401 for git-lfs compatibility
  def emu_visibility_enforce(target)
    if anonymous_request? && !NON_401_ROUTES.include?(route_pattern)
      # 401 for anon requests
      deliver_error!(401)
    else
      # 404 for authenticated requests
      send_not_found
    end
  end

  # Override default blanket 404 to 401 for git-lfs compatibility
  def tenant_verification_enforce(target)
    if anonymous_request? && !NON_401_ROUTES.include?(route_pattern)
      # 401 for anon requests
      deliver_error!(401)
    else
      # 404 for authenticated requests
      send_not_found
    end
  end

  # LFS will be killed when password auth for git is deprecated
  def password_auth_blocked?
    return false if GitHub.git_password_auth_supported?

    logged_in?
  end

  # used to override `from` metric tag in app/platform/authorization.rb:api_auth() and
  # lib/github/authentication/attempt.rb:instrument()
  def source
    :internal_lfs
  end

  post "/internal/lfs/auth", operation_id: :internal do
    @route_owner = "@github/git-protocols"
    ActiveRecord::Base.connected_to(role: :reading) do
      abilities = repo_abilities
      if abilities.blank?
        deliver_error!(@auth_error_status || 401, message: "Invalid repository")
      end

      output = {
        repository: { id: @current_repo.id, abilities: abilities, ability: abilities.first },
      }

      if logged_in?
        output[:viewer] = if logged_in_as_user?
          { id: current_user.id, login: current_user.display_login, type: "user" }
        else
          { id: @authenticated_key.id, login: @current_repo.name_with_display_owner, type: "deploy-key" }
        end
      end

      deliver_raw output
    end
  end

  def require_request_hmac?
    true
  end

  def filter_ids(ids)
    ids = Array(ids)
    ids.map! { |i| i.to_i }
    ids.uniq!
    ids.delete_if { |i| i < 0 }
    ids
  end

  post "/internal/lfs/users", operation_id: :internal do
    @route_owner = "@github/git-protocols"

    ActiveRecord::Base.connected_to(role: :reading) do
      user_ids = filter_ids(@json_body["user_ids"])
      key_ids = filter_ids(@json_body["key_ids"])

      if user_ids.size > 100 || key_ids.size > 100
        deliver_error! 400, message: "Too many ids: #{user_ids.size}/#{key_ids.size}"
      end

      output = { users: {}, keys: {} }
      User.where(id: user_ids).each do |u|
        next if u.suspended?
        output[:users][u.id.to_s] = { login: u.display_login }
      end if user_ids.size > 0

      PublicKey.where(id: key_ids).each do |k|
        next if k.repository.nil?
        fingerprint = if GitHub.multi_tenant_enterprise?
          k.fingerprint_sha256.split("_")[0]
        else
          k.fingerprint_sha256
        end
        output[:keys][k.id.to_s] = { nwo: k.repository.name_with_display_owner, fingerprint: fingerprint }
      end if key_ids.size > 0

      deliver_raw output
    end
  end

  post "/internal/lfs/verify", operation_id: :internal do
    @route_owner = "@github/git-protocols"
    @current_repo = load_repository(@json_body)
    deliver_error!(400, message: "No valid repository") unless @current_repo

    # Accept only hashes with an exact length of 64 characters
    requested_oids = Array(@json_body["oids"])
    requested_oids.delete_if { |i| i.length != 64 }
    requested_oids.uniq!
    deliver_error!(400, message: "No valid LFS object IDs") unless requested_oids.size > 0

    unknown = T.let([], T::Array[String])
    requested_oids.in_groups_of(LFS_VERIFY_BATCH_SIZE, false) do |oids|
      query_oids = {
        oid: oids,
        repository_network_id: @current_repo.network_id,
        state: Media::Blob::states[:verified],
      }

      # The "/internal/lfs/verify" call is usually made right after new
      # Media::Blobs have been pushed. In order to reduce the risk of
      # races we perform the query explicitly not against the read-only
      # replica.
      verified_count = Media::Blob.where(query_oids).count

      if oids.length != verified_count
        # Query the actual object IDs only in the unhappy path
        verified_oids = Media::Blob.where(query_oids).pluck(:oid)
        unknown += oids - verified_oids
      end

      break if unknown.length > 0
    end

    log_data.update(
      "lfs_missing_objects_count".intern => unknown.length,
    )

    deliver_raw(unknown: unknown)
  end

  post "/internal/lfs/download-urls", operation_id: :internal do
    @route_owner = "@github/git-protocols"
    @current_repo = load_repository(@json_body)
    ActiveRecord::Base.connected_to(role: :reading) do
      deliver_error!(404, message: "No valid repository") unless @current_repo

      # Accept only hashes with an exact length of 64 characters
      requested_oids = Array(@json_body["oids"])
      requested_oids.delete_if { |i| i.length != 64 }
      requested_oids.uniq!
      deliver_error!(400, message: "No valid LFS object IDs") unless requested_oids.size > 0

      control_access :get_media_blob,
          repo: @current_repo,
          allow_integrations: true,
          allow_user_via_granular_actor: true

      result = {}
      requested_oids.in_groups_of(LFS_URL_GENERATION_BATCH_SIZE) do |oids|
        query_oids = {
          oid: oids,
          repository_network_id: @current_repo.network_id,
          state: Media::Blob::states[:verified],
        }

        result.merge!(Media::Blob.where(query_oids).map { |blob| [blob.oid, blob.download_link(actor: current_user, repo: @current_repo)] }.to_h)
      end

      deliver_error!(404, message: "No LFS objects found") if result.empty?
      deliver_raw(links: result)
    end
  end

  def repo_abilities
    return [] unless @current_repo

    options = {
        repo: @current_repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    }

    # This is already handled in the options above.
    # rubocop:disable GitHub/AllowIntegrations
    # rubocop:disable GitHub/AllowUserViaGranularActor
    perms = []
    if @lfs_operation == :upload
      perms << :admin if access_allowed?(:override_media_blob_locks, **options)
      perms << :push  if access_allowed?(:write_media_blob_locks, **options)
    end
    perms << :pull if access_allowed?(:read_media_blob_locks, **options)
    # rubocop:enable GitHub/AllowUserViaGranularActor
    # rubocop:enable GitHub/AllowIntegrations
    perms
  end

  # This is called before the actual request since Api::App#populate_context_with_authentication_details
  # calls #logged_in?. This parses the request body so it can load the repository,
  # which is needed to verify a remote auth token.
  def attempt_login
    # prevents this method being called multiple times when called anonymously
    return if @json_body
    @json_body = receive(Hash, required: true, check_encoding: false)
    @current_user = T.let(nil, T.nilable(User))
    @deploy_key = nil

    # These are the only endpoints that need to auth as a user
    return unless request.path_info =~ %r[\A/internal/lfs/(auth|download-urls)\z]
    @endpoint = T.must(Regexp.last_match)[1]

    @current_repo = load_repository(@json_body)

    login_from_api_auth
    login_from_remote_auth unless @current_user

    if @current_repo && GitHub.flipper[:lfs_disable].enabled?(@current_repo)
      deliver_error! 404
    end

    @auth_error_status = 401

    if logged_in?
      @auth_error_status = 403
      if (@current_user && GitHub.flipper[:lfs_disable].enabled?(@current_user)) || (@current_repo && GitHub.flipper[:lfs_disable].enabled?(@current_repo))
        deliver_error! 404
      end

      @lfs_operation ||= :upload
      return unless @current_user && @current_user.suspended?
      @current_user = nil
    end

    return unless GitHub.private_mode_enabled?
    return unless @endpoint == "auth"

    deliver_error!(@auth_error_status, message: "Must authenticate to access this API.")
  end

  def login_from_remote_auth
    return unless @current_repo
    token = Api::RequestCredentials.token_from_scheme(env, "remoteauth")
    return if token.blank?

    ActiveRecord::Base.connected_to(role: :reading) do
      operations = [:upload, :download]
      operations.each do |op|
        result = verify_token(token, op)

        log_data.update(
          "lfs_media_#{op}_scope".intern => result.reason,
        )

        if result.valid?
          @lfs_operation = op
          @remote_token_auth = true
          @current_user, @authenticated_key = case
          when user = Media::Token.user_for_token(result)
            # Signed auth token or GitAuth token for user.
            [user, nil]
          when key = Media::Token.deploy_key_for_token(result)
            # GitAuth token for deploy key.
            [nil, key]
          else
            # Something else.  The token was valid, but it grants no access.
            [nil, nil]
          end
          return
        end
      end
    end
  end

  def verify_token(token, op)
    scope = Media.auth_scope(@current_repo.id, op.to_s, deploy_key_id: deploy_key_id)

    if GitHub::Authentication::GitAuth::SignedAuthToken.valid_format?(token)
      GitHub::Authentication::GitAuth::SignedAuthToken.verify(
        token: token,
        scope: scope,
        repo: @current_repo,
      )
    else
      User.verify_signed_auth_token(
        token: token,
        scope: scope,
      )
    end
  end

  def deploy_key_id
    Media.deploy_key_id_from_env(env)
  end

  def logged_in?
    logged_in_as_user? || logged_in_as_key?
  end

  def deploy_key?
    @deploy_key
  end

  def authenticated_for_private_mode?
    true
  end

  def rate_limit_status_code
    429
  end

  def load_repository(body)
    repo_name = body["repository"]
    repo_id = body["repository_id"]
    if repo_name.blank? && repo_id.blank?
      deliver_error! 400, message: "repository key is empty"
    end

    repo = Repository.with_name_with_owner(repo_name)
    repo ||= RepositoryRedirect.find_redirected_repository(repo_name)
    repo ||= Repository.find_by(id: repo_id.to_i)
    repo = nil if repo && repo.access.disabled?

    repo
  end

  def check_allowlist_for_request_limiting
    GitHub::Limiters::Middleware.skip_limit_checks(env)
  end
end
