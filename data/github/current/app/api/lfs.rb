# typed: true
# frozen_string_literal: true

class Api::Lfs < Api::App

  rate_limit_as Api::RateLimitConfiguration::LFS_FAMILY

  NON_401_ROUTES = [
    "/lfs/:owner/:repo/objects",
    "/lfs/:owner/:repo/objects/:oid"
  ]

  # Override default blanket 404 to 401 for git-lfs compatibility
  def emu_visibility_enforce(target)
    if legacy_apis_disabled?
      if invalid_credentials?
        # 403 for requests with invalid auth
        reject_for_bad_credentials!
      elsif anonymous_request?
        # 401 for anonymous requests
        deliver_error!(401)
      else
        # 404 for authenticated requests
        send_not_found
      end
    else
      if invalid_credentials?
        # 403 for requests with invalid auth
        reject_for_bad_credentials!
      elsif anonymous_request? && !NON_401_ROUTES.include?(route_pattern)
        # 401 for non legacy API anon requests
        deliver_error!(401)
      else
        # 404 for authenticated requests
        send_not_found
      end
    end
  end

  def tenant_verification_enforce(target)
    if legacy_apis_disabled?
      if invalid_credentials?
        # 403 for requests with invalid auth
        reject_for_bad_credentials!
      elsif anonymous_request?
        # 401 for anonymous requests
        deliver_error!(401)
      else
        # 404 for authenticated requests
        send_not_found
      end
    else
      if invalid_credentials?
        # 403 for requests with invalid auth
        reject_for_bad_credentials!
      elsif anonymous_request? && !NON_401_ROUTES.include?(route_pattern)
        # 401 for non legacy API anon requests
        deliver_error!(401)
      else
        # 404 for authenticated requests
        send_not_found
      end
    end
  end

  # LFS will be killed when password auth for git is deprecated
  def password_auth_blocked?
    false
  end

  # used to override `from` metric tag in app/platform/authorization.rb:api_auth() and
  # lib/github/authentication/attempt.rb:instrument()
  def source
    :lfs
  end

  MEDIA_MIME_TYPES = Set.new(%w(
    application/vnd.git-lfs+json
  ))

  def legacy_apis_disabled?
    return @disable_legacy_apis if defined?(@disable_legacy_apis)
    @disable_legacy_apis = begin
      repo = Repository.nwo(repo_nwo_from_path)
      repo = find_redirected_repo_from_path if repo.nil?
      if repo && repo.vexi_id
        FeatureFlag.vexi.enabled?("disable_legacy_lfs_apis", repo, default: false)
      else
        false
      end
    end
  end

  # This is triggered before the sinatra request blocks. So, this attempts to
  # get the batch operation out of the parsed json body. This won't work for
  # legacy POST requests. #login_from_remote_auth will just fall back to
  # checking the request method.
  def attempt_login
    # prevents this method being called multiple times when called anonymously
    return if @json_body
    @json_body = receive(Hash, required: false, check_encoding: false) || {}
    @lfs_operation = if legacy_apis_disabled?
      case request.path_info
      when /\/[a-f0-9]{64}\/confirm\z/i, /\/[a-f0-9]{64}\/verify_url\z/i then :verify
      end
    else
      case request.path_info
      when /\/[a-f0-9]{64}\/confirm\z/i, /\/[a-f0-9]{64}\/verify(_url)?\z/i then :verify
      end
    end

    if @lfs_operation.nil? && request.request_method == "POST"
      case @json_body["operation"]
      when "download"
        @lfs_operation = :batch_download
        @lfs_batch_encoder = method(:encode_download_batch)
      when "upload"
        @lfs_operation = :batch_upload
        @lfs_batch_encoder = method(:encode_upload_batch)
      end
    end

    @current_user = nil
    login_from_api_auth
    login_from_remote_auth unless @current_user
  end

  post "/lfs/:owner/:repo/objects/batch", operation_id: :ignored do
    @route_owner = "@github/lfs"
    validate_json_hash! :request, @json_body || {}

    if !@lfs_operation
      deliver_error!(422, message: "Invalid operation: #{@json_body["operation"].inspect}")
    end

    objects = ActiveRecord::Base.connected_to(role: :reading) do
      if Media::Blob.over_quota?(current_repository)
        GitHub.dogstats.increment("lfs.quota")
        doc_url = nil
        if current_repository.in_organization?
          doc_url = "#{GitHub.help_url}/articles/purchasing-additional-storage-and-bandwidth-for-an-organization/"
        else
          doc_url = "#{GitHub.help_url}/articles/purchasing-additional-storage-and-bandwidth-for-a-personal-account/"
        end
        deliver_error!(403, message: "This repository is over its data quota. Account responsible for LFS bandwidth should purchase more data packs to restore access.", documentation_url: doc_url)
      end

      if @lfs_operation == :batch_upload
        control_access :create_media_blob,
          repo: current_repository,
          challenge: !request_credentials_present?,
          allow_integrations: true,
          allow_user_via_granular_actor: true
      else
        control_access :get_media_blob,
          repo: current_repository,
          challenge: !request_credentials_present?,
          allow_integrations: true,
          allow_user_via_granular_actor: true
      end

      ensure_budget_remaining!

      objs = Array(@json_body["objects"])

      if objs.size.zero?
        increment_stat :empty
        deliver_error!(422, message: "No objects specified.")
      elsif objs.size > Media::Blob::BATCH_LIMIT
        increment_stat :too_many_objects
        deliver_error!(413, message: "More than #{Media::Blob::BATCH_LIMIT} objects specified.")
      end

      objs
    end

    deliver_raw @lfs_batch_encoder.call(objects)
  end

  def encode_download_batch(objects)
    counts = { archived: 0, missing: 0, ok: 0 }
    objects = parse_objects(objects)
    oids = objects.map { |o| o[:oid] }
    blobs = ActiveRecord::Base.connected_to(role: :reading) { ::Media::Blob.fetch_all(current_repository, oids) }

    encode_batch(objects, blobs) do |blob, obj|
      if blob.try(:archived?)
        obj[:error] = {
          code: 410,
          message: "Object does not exist on the server",
        }
        counts[:archived] += 1
      elsif !blob.try(:verified?)
        obj[:error] = {
          code: 404,
          message: "Object does not exist on the server",
        }
        counts[:missing] += 1
      else
        obj[:actions] = {
          download: blob.download_link(actor: current_user, repo: current_repository, key: @authenticated_key),
        }
        counts[:ok] += 1
      end
    end
  ensure
    counts.each do |stat, num|
      increment_stat(stat, count: num) if num > 0
    end if counts
  end

  def encode_upload_batch(objects)
    counts = { invalid: 0, exist: 0, accept: 0 }
    objects = parse_objects(objects)
    blobs = ::Media::Blob.init_all(current_repository,
      pusher: current_user,
      objects: objects,
    )

    encode_batch(objects, blobs) do |blob, obj|
      if blob.errors.any?
        counts[:invalid] += 1
        obj[:error] = {
          code: 422,
          message: blob.errors.full_messages.to_sentence,
        }
        next
      end

      if blob.verified?
        counts[:exist] += 1
        next
      end

      counts[:accept] += 1

      obj[:actions] = {
        upload: blob.lfs_upload_link(actor: current_user, repo: current_repository, key: @authenticated_key),
      }

      unless GitHub.storage_cluster_enabled?
        obj[:actions][:verify] = {
          href: "#{GitHub.lfs_server_url}/#{params[:owner]}/#{params[:repo]}/objects/#{blob.oid}/verify",
          header: {
            "Authorization" => "RemoteAuth #{blob.verify_token(current_user, current_repository, @authenticated_key)}",
            "Accept" => "application/vnd.git-lfs+json",
          },
        }
      end
    end
  ensure
    counts.each do |stat, num|
      increment_stat(stat, count: num) if num > 0
    end if counts
  end

  def parse_objects(objects)
    objects.map do |o|
      oid = o["oid"]
      if oid.blank?
        deliver_error!(422, message: "Invalid OID in payload")
      end
      { oid: oid, size: o["size"].to_i }
    end
  end

  def encode_batch(objects, blobs, &block)
    blobs_by_oid = blobs.index_by(&:oid)
    objects.each do |obj|
      blob = blobs_by_oid[obj[:oid]]
      if blob && blob.size != obj[:size]
        obj[:error] = {
          code: 422,
          message: "Object #{obj[:oid]} is not #{obj[:size]} bytes",
        }
      else
        yield blob, obj
      end
    end

    { objects: objects }
  end

  def validate_json_hash!(schema_type, hash)
    validated, errors = SCHEMA[schema_type].validate(hash)
    if !validated
      deliver_error!(422, message: "JSON Validation errors in #{schema_type}: #{errors.map(&:to_s).to_sentence}")
    end
  end

  get "/lfs/:owner/:repo/objects/:oid", operation_id: :ignored do
    @route_owner = "@github/lfs"
    @lfs_operation = :download

    if legacy_apis_disabled?
      deliver_error!(404)
    end

    control_access :get_media_blob,
      repo: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blob = ActiveRecord::Base.connected_to(role: :reading) { ::Media::Blob.fetch(current_repository, params[:oid]) }

    if blob.try(:archived?)
      increment_stat :archived
      deliver_error!(410)
    end

    if !blob.try(:viewable?)
      increment_stat :missing
      deliver_error!(404)
    end

    ensure_budget_remaining!

    increment_stat :ok

    deliver_raw({
      :oid => blob.oid,
      :size => blob.size,
      "_links" => {
        self: {
          href: url("#{GitHub.api_url}/lfs/#{params[:owner]}/#{params[:repo]}/objects/#{blob.oid}"),
        },
        download: blob.download_link(actor: current_user, repo: current_repository, key: @authenticated_key),
      },
    })
  end

  post "/lfs/:owner/:repo/objects", operation_id: :ignored do
    @route_owner = "@github/lfs"
    @lfs_operation = :upload

    if legacy_apis_disabled?
      deliver_error!(404)
    end

    control_access :create_media_blob,
      repo: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_budget_remaining!

    blob = ::Media::Blob.init_all(current_repository,
      pusher: current_user,
      objects: [{ oid: @json_body["oid"], size: @json_body["size"] }],
    ).first

    if blob.errors.any?
      increment_stat :invalid
      deliver_error! 422, errors: blob.errors
    end

    links = {
      upload: blob.lfs_upload_link(actor: current_user, repo: current_repository, key: @authenticated_key),
    }

    unless GitHub.storage_cluster_enabled?
      links[:verify] = {
        href: url("#{GitHub.api_url}/lfs/#{params[:owner]}/#{params[:repo]}/objects/#{blob.oid}/verify"),
        header: {
          "Authorization" => "RemoteAuth #{blob.verify_token(current_user, current_repository, @authenticated_key)}",
          "Accept" => "application/vnd.git-lfs+json",
        },
      }
    end

    increment_stat(blob.verified? ? :exist : :accept)

    deliver_raw({
      "_links" => links,
    }, status: blob.verified? ? 200 : 202)
  end

  # Not used in Enterprise because Alambic handles this step through the
  # Internal API.
  post "/lfs/:owner/:repo/objects/:oid/verify", operation_id: :ignored do
    @route_owner = "@github/lfs"

    if legacy_apis_disabled?
      deliver_error!(404)
    end

    repo = current_repository

    if GitHub.storage_cluster_enabled?
      deliver_error!(400, message: "Storage cluster doesn't require or support verify.")
    end

    control_access :create_media_blob,
      repo: repo,
      challenge: !request_credentials_present?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blob = ::Media::Blob.fetch(repo, params[:oid])
    if !blob
      return deliver_error(404)
    end

    if blob.viewable?
      increment_stat :verified
      return deliver_empty
    end

    verified = begin
      blob.verify!
    rescue ActiveRecord::RecordInvalid => err
      Failbot.report_user_error(err)
      false
    end

    if !verified
      increment_stat :bad
      return deliver_error(422)
    end

    GitHub.dogstats.histogram("lfs.verified_size", blob.size, tags: ["action:verify"])
    increment_stat :ok
    deliver_empty
  end

  # Used by lfs-server to retrieve the S3 URL to make the verification request.
  get "/lfs/:owner/:repo/objects/:oid/verify_url", operation_id: :ignored do
    @route_owner = "@github/lfs"
    repo = current_repository

    control_access :create_media_blob,
      repo: repo,
      challenge: !request_credentials_present?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blob = ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) { ::Media::Blob.fetch(repo, params[:oid]) }
    if !blob
      return deliver_error(404)
    end

    deliver_raw({
      :oid => blob.oid,
      :size => blob.size,
      "_links" => {
        self: {
          href: url("#{GitHub.api_url}/lfs/#{params[:owner]}/#{params[:repo]}/objects/#{blob.oid}"),
        },
        verify: {
          href: blob.verify_url,
        },
        confirm: {
          href: url("#{GitHub.api_url}/lfs/#{params[:owner]}/#{params[:repo]}/objects/#{blob.oid}/confirm"),
          header: {
            "Authorization" => "RemoteAuth #{blob.verify_token(current_user, current_repository, @authenticated_key)}",
            "Accept" => "application/vnd.git-lfs+json",
          },
        },
      },
    })
  end

  # Used by lfs-server to mark the blob as verified after performing S3 HEAD check.
  post "/lfs/:owner/:repo/objects/:oid/confirm", operation_id: :ignored do
    @route_owner = "@github/lfs"
    repo = current_repository

    control_access :create_media_blob,
      repo: repo,
      challenge: !request_credentials_present?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blob = ::Media::Blob.fetch(repo, params[:oid])
    if !blob
      return deliver_error(404)
    end

    if blob.viewable?
      increment_stat :verified
      return deliver_empty
    end

    verified = begin
      blob.set_verified_state!
      true
    rescue ActiveRecord::RecordInvalid => err
      Failbot.report_user_error(err)
      false
    end

    if !verified
      increment_stat :bad
      return deliver_error(422)
    end

    GitHub.dogstats.histogram("lfs.verified_size", blob.size, tags: ["action:confirm"])
    increment_stat :ok
    deliver_empty
  end

  # Used to ensure the haproxy info/lfs route is properly set up.
  get "/lfs/:owner/:repo/_ping", operation_id: :internal, skip_rate_limit: true do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/lfs"
    "ok"
  end

  def self.parse_schema(json_file)
    json = File.read(json_file)
    data = GitHub::JSON.parse(json)
    JsonSchema.parse!(data)
  end

  SCHEMA = {
    request: parse_schema(Rails.root.join("app/api/schemas/lfs/v1-batch-request.json")),
    response: parse_schema(Rails.root.join("app/api/schemas/lfs/v1-batch-response.json")),
  }

  def authenticated_key
    @authenticated_key
  end

  def authenticated_for_private_mode?
    @current_user || @authenticated_key
  end

  def logged_in?
    logged_in_as_user? || logged_in_as_key?
  end

  private

  # Override Api::App#repo_nwo_from_path.
  #
  # For Api::LFS, authentication sometimes happens via a signed auth token. That
  # token only provides authentication for a specific repository. The repository
  # is identified by the request path, and this method is used to determine the
  # repository name-with-owner from the path. Because authentication happens in
  # a `before` block, Sinatra has not yet populated `params` from the request
  # before (i.e., ENV["PATH_INFO"]), so we can't use `params[:owner]` and
  # `params[:repo]` to determine the repository name-with-owner. Instead, we
  # must resort to parsing the request path to in order to determine the
  # name-with-owner.
  def repo_nwo_from_path
    @repo_nwo_from_path ||= begin
      # /lfs/:owner/:repo/objects/...
      path = request.path_info.to_s.split("/")
      "#{path[2]}/#{path[3]}"
    end
  end

  # Attempts to log in with a RemoteAuth token.  Returns true if the
  # `Authorization` header starts with `RemoteAuth`.  If a remote auth login is
  # attempted, don't bother trying another login method like OAuth.
  def login_from_remote_auth
    return false unless token = token_from_header
    @remoteauth_attempted = true

    ActiveRecord::Base.connected_to(role: :reading) do
      # this is set at the top of #attempt_login
      if @lfs_operation == :verify
        oid = request.path_info.split("/")[-2]
        scope = Media::Blob.verify_scope(current_repository.network.id, oid)
        verify, @remote_token_auth, @current_user, @authenticated_key = verify_token(token, scope)
        reject_for_bad_credentials! unless @current_user || @authenticated_key

        log_data.update(
          lfs_auth_scope: scope,
          lfs_verify_reason: verify.reason,
        )

        return true
      end

      operation = if @lfs_operation
        # batch api
        @lfs_operation.to_s.split("_").last
      else
        # legacy api
        if legacy_apis_disabled?
          return false
        end
        OP_METHODS[request.request_method]
      end

      deploy_key_id = Media.deploy_key_id_from_env(env)

      auth_scope = Media.auth_scope(current_repository.id, operation, deploy_key_id: deploy_key_id)
      verify, @remote_token_auth, @current_user, @authenticated_key = verify_token(token, auth_scope)
      reject_for_bad_credentials! unless @current_user || @authenticated_key

      log_data.update(
        lfs_deploy_key_header: env["HTTP_GITHUB_DEPLOY_KEY"].inspect,
        lfs_auth_scope: auth_scope,
        lfs_verify_reason: verify.reason,
      )

      verify_deploy_key!(@lfs_operation, current_repository, deploy_key_id)

      if logged_in? && @lfs_operation != :verify
        @lfs_auth = :ssh
      end

      true
    end
  end

  def verify_token(token, scope)
    verify = verify_gitauth_token(token, scope)

    if user = Media::Token.user_for_token(verify)
      # Token for user.
      [verify, verify.valid?, user, nil]
    elsif key = Media::Token.deploy_key_for_token(verify)
      # Token for deploy key.
      [verify, verify.valid?, nil, key]
    else
      # Either invalid or valid with no useful authentication.
      [verify, false, nil, nil]
    end
  end

  def verify_gitauth_token(token, scope)
    GitHub::Authentication::GitAuth::SignedAuthToken.verify(
      token: token,
      scope: scope,
      repo: current_repository,
    )
  end

  def rate_limit_status_code
    429
  end

  # Matches request method to a Media scope's operation.
  OP_METHODS = {
    "GET" => :download,
    "HEAD" => :download,
    "POST" => :upload,
  }.freeze

  def current_repository
    @current_repository ||= ActiveRecord::Base.connected_to(role: :reading) do
      if (MEDIA_MIME_TYPES & medias.map(&:to_s)).empty?
        deliver_error!(406, message: "Not Acceptable")
      end

      repo = this_repo
      if repo && repo.access.disabled?
        deliver_error!(env["REQUEST_METHOD"] == "GET" ? 410 : 403)
      end
      repo
    end
  end

  # Internal: Always redirect LFS clients to the proper LFS endpoint:
  #
  #     https://github.com/OWNER/REPO.git/info/lfs/*
  #
  def this_repo_redirection(path, requested_nwo, redirected_repo)
    return super if Rails.env.development? # lfs endpoint doesn't work with github.dev
    pos = path.index(requested_nwo)
    pos += requested_nwo.size
    suffix = path[pos..-1]
    "/#{redirected_repo.name_with_owner_for_api(use: :display)}.git/info/lfs#{suffix}"
  end

  # The LFS API url looks like:
  #
  #     https://github.com/OWNER/REPO.git/info/lfs/*
  #
  def api_url(path)
    GitHub.url + path
  end

  # LFS API handles missing repos differently
  def missing_repository_status_code
    request_credentials_present? ? 403 : 401
  end

  def missing_repository_options
    request_credentials_present? ? { message: "Bad credentials" } : {}
  end

  def reject_for_bad_credentials!
    if request_credentials_present?
      GitHub.dogstats.increment("api.authentication", tags: ["reason:invalid", "valid:false"])
      deliver_error! 403, message: "Bad credentials"
    else
      deliver_error! 401
    end
  end

  # This covers the case in MT where we consider the request anonymous but there are
  # some credentials, which can happen on renamed repositories due to ordering
  def invalid_credentials?
    anonymous_request? && request_credentials_present?
  end

  def request_credentials_present?
    @remoteauth_attempted || request_credentials.credentials_present?
  end

  def deliver_error(status, options = {})
    if status == 401
      headers["LFS-Authenticate"] = %(Basic realm="GitHub")
    end

    super
  end

  LFS_NEED_PUSH = "You need Push access to upload Git LFS objects.".freeze
  LFS_DISABLED = "Git LFS is disabled for this repository.".freeze
  LFS_DISABLED_GLOBAL = "Git LFS is disabled for your instance.".freeze
  LFS_DISABLED_CACHE_REPLICA = "Git LFS pushes are disabled on repository cache replicas.".freeze

  def control_access(access_type, options = {})
    if (MEDIA_MIME_TYPES & medias.map(&:to_s)).empty?
      deliver_error!(406, message: "Not Acceptable")
    end

    if logged_in? && access_type == :create_media_blob
      if GitHub.enterprise? && current_repository.running_on_cache_server?
        deliver_error!(403, message: LFS_DISABLED_CACHE_REPLICA)
      end

      ensure_public_fork_accepts_lfs!

      if current_repository.public? || access_allowed?(:get_media_blob, repo: current_repository, allow_integrations: false, allow_user_via_granular_actor: false)
        set_forbidden_message LFS_NEED_PUSH
      end
    end

    super(access_type, options)

    if !GitHub.git_lfs_config_enabled?
      deliver_error!(403, message: LFS_DISABLED_GLOBAL)
    elsif !current_repository.git_lfs_enabled?
      deliver_error!(403, message: LFS_DISABLED)
    end
  end

  def ensure_public_fork_accepts_lfs!
    return if GitHub.enterprise?
    return if !current_repository.public?
    return if Media::Blob.in_network?(current_repository.network)
    return if current_repository.network_root?
    return if current_repository.root.pushable_by?(current_user)

    msg = "@%s can not upload new objects to public fork %s" % [
      current_user.login_for_api,
      current_repository.name_with_owner_for_api,
    ]

    deliver_error!(403, message: msg)
  end

  # Matches LFS/media scope operation to billing SKU.
  SKUS = {
    batch_download: "git_lfs_bandwidth",
    batch_upload:   "git_lfs_storage",
    download:       "git_lfs_bandwidth",
    upload:         "git_lfs_storage",
  }.freeze

  def ensure_budget_remaining!
    ActiveRecord::Base.connected_to(role: :reading) do
      if ::Media::Blob.budget_exceeded?(sku: SKUS[@lfs_operation], repository: current_repository, actor: current_user)
        deliver_error!(403, message: "This repository exceeded its LFS budget. The account responsible for the budget should increase it to restore access.")
      end
    end
  end

  def verify_deploy_key!(operation, repository, key_id)
    return if key_id.nil?

    key = PublicKey.find_by(id: key_id)

    if key.nil? || !key.verified? || key.repository_id != repository.id || (authenticated_key && authenticated_key.id != key_id)
      GitHub.dogstats.increment("lfs.ssh_resp", tags: ["status:api_invalid_key"])
      deliver_error!(403, message: "Invalid deploy key for #{current_repository.name_with_owner_for_api}")
    end

    if key.read_only? && write_operation?(operation)
      GitHub.dogstats.increment("lfs.ssh_resp", tags: ["status:api_readonly_key"])
      deliver_error!(403, message: "Read-only deploy key for #{current_repository.name_with_owner_for_api} action: #{operation}")
    end
  end

  def write_operation?(operation)
    operation != :batch_download
  end

  def token_from_header
    Api::RequestCredentials.token_from_scheme(env, "remoteauth")
  end

  def self.acceptable_media_types # rubocop:disable Lint/IneffectiveAccessModifier
    MEDIA_MIME_TYPES
  end

  def record_stats
    return unless @lfs_operation
    GitHub.dogstats.timing("lfs.requests", request_elapsed_time_in_ms, tags: ["op:#{@lfs_operation}"])
    GitHub.dogstats.timing("lfs.mysql", GitHub::MysqlInstrumenter.query_time * 1000, tags: ["op:#{@lfs_operation}"])
    GitHub.dogstats.increment("lfs.auth", tags: ["auth:#{detect_auth}"])
  end

  def detect_auth
    @lfs_auth || super
  end

  def increment_stat(suffix, count: 1)
    ns = @lfs_operation
    raise "No @lfs_operation!" if ns.blank?
    GitHub.dogstats.count("lfs.objects", count,
      tags: ["op:#{@lfs_operation}", "state:#{suffix}"])
  end

  def default_documentation_url
    if GitHub.enterprise?
      "https://docs.github.com/enterprise"
    else
      GitHub.contact_support_url
    end
  end
end
