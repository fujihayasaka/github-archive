# typed: true
# frozen_string_literal: true

require "securerandom"
require "rack"
require "github/dgit"
require "github/dns"
require "rack/request_logger"

require_relative "./authentication/attempt"
require_relative "../audit/auth_data"

module GitHub
  # Basic repository read/write permissions checking used for all native
  # git access to user, wiki, and gist repositories. The following
  # components rely on this implementation for authorization:
  #
  #  - babeld unified git+svn proxy (https://github.com/github/babeld)
  #  - LFS: app/models/media/git_auth.rb
  class RepoPermissions
    extend Scientist

    # Any values logged that may contain sensitive information are substituted
    # with this string.
    FILTERED = "[FILTERED]"

    SERVICE_NAME = "github/gitauth"
    PERMISSION_DENIED = "permission denied"
    HOOK_DECLINED = "pre-receive hook declined"

    GOTAUTH_SERVICE_NAME = "gotauth"

    # Determine how the user authenticated.
    def self.member_auth_type(member)
      case
      when member.nil?
        nil
      when member.bot?
        "bot"
      when member.using_auth_via_oauth_application?
        "user_via_oauth"
      when member.using_auth_via_integration?
        "user_via_integration"
      when member.using_auth_via_user_programmatic_access?
        "user_via_user_programmatic_access"
      else
        "user"
      end
    end

    # Our caller is hopefully using Rack::RequestLogger middleware. We can use
    # our request env to add additional data to our logging context.
    #
    # Note: You'll see something similiar in Api::App and any other controller
    # base-class
    def self.log_data(request)
      request.env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= HashWithIndifferentAccess.new
    end

    def self.log_exception(request, e, data = {})
      log_context = data.merge({
        :exception => e,
        "code.namespace" => "GitHub::RepoPermissions",
        "gh.request_id" => Rack::RequestId.get(request.env),
      })

      GitHub.logger.error("Repo permission error", log_context)

      span = self.rack_span
      span.add_event("exception", attributes: { "exception.type" => e.class.name })
    end

    # Private: The controller name to use for failbot and wherever else needed.
    CONTROLLER = "GitHub::RepoPermissions"

    # Private: The default action for the action key in the application log data
    # key in env. Overridden where it makes sense to something more specific
    # (e.g. gitauth or commit_refs).
    DEFAULT_ACTION = "unknown"

    # Rack handler that wraps request handling in read only database connection
    def self.call(env)
      # Allowlist all gitauth actions for tagging
      env[GitHub::TaggingHelper::PROCESS_SERVICE_KEY] = SERVICE_NAME

      action = DEFAULT_ACTION
      request = Rack::Request.new(env)

      ctx = initial_context(request)
      GitHub.context.push(ctx.merge(connections: ApplicationRecord.connection_info))
      Audit.context.push(ctx)

      Failbot.push({
        "catalog_service": SERVICE_NAME,
        "code.namespace": CONTROLLER,
        "gh.request_id": Rack::RequestId.get(env),
      })

      log_data(request).merge!({
        "code.namespace" => "GitHub::RepoPermissions",
        "code.function" => __method__,
        "http.request.header.x_original_user_agent" => request.env["HTTP_X_ORIGINAL_USER_AGENT"],
        "gh.catalog_service" => SERVICE_NAME
      })

      span = self.rack_span
      span.name = "#{request.request_method} #{request.path}"
      span.add_attributes("gh.catalog_service" => SERVICE_NAME, "code.namespace" => CONTROLLER)

      db_source_action = case request.path
      when "/_gitauth"
        "gitauth"
      when "/_commit_refs"
        "commit_refs"
      end

      unless db_source_action.nil?
        db_source_controller = GitHub::TaggingHelper.formatted_controller(CONTROLLER)
        db_source_method = GitHub::TaggingHelper.request_method(request.env)
        GitHub.context.push(db_call_source_datadog_tags: [
          "source_type:request",
          "controller:#{db_source_controller}",
          "method:#{db_source_method}",
          "action:#{db_source_action}",
          "source:request-#{db_source_method}-#{db_source_controller}-#{db_source_action}"
        ])
      end

      GitHub.logger.with_named_tags("gh.request_id" => Rack::RequestId.get(request.env)) do

        case request.path
        when "/_gitauth"
          action = "gitauth"
          ActiveRecord::Base.connected_to(role: :reading) do
            handle_request(request)
          end
        when "/_commit_refs"
          action = "commit_refs"
          span.set_attribute("rpc.method", "commit-refs")
          log_data(request)["rpc.method"] = "commit-refs"

          body = commit_refs(request)

          span.add_event(body["err"]) if body["err"].present?
          log_data(request)["http.ok"] = body["ok"]

          headers = {
            "Content-Type" => "application/json",
          }
          request_id = Rack::RequestId.get(request.env)
          headers["X-GitHub-Request-Id"] = request_id unless request_id.nil?
          [200, headers, [GitHub::JSON.encode(body)]]
        when "/_hello_world"
          action = "hello_world"
          hello_world(request)
        else
          action = "404"
          [
            404, { "Content-Type" => "text/plain" },
            ["unknown gitauth call"]
          ]
        end
      end
    ensure
      # These get plucked out by GitHub::Middleware::Stats to help categorize
      # gitauth requests in DataDog.
      env["process.api.controller"] ||= CONTROLLER
      env["github.api.route"] ||= action
    end

    def self.hello_world(request)
      headers = {
        "Content-Type" => "application/json",
        "X-GitHub-Request-Id" => Rack::RequestId.get(request.env),
      }

      [
        200,
        headers,
        [
          GitHub::JSON.encode({ "hello" => "world" }),
        ],
      ]
    end

    def self.commit_refs(request)
      body = GitAuth::CommitRefsRequestBody.new(request.body.read)

      commit_refs = GitAuth::CommitRefs.new(body)

      log_data(request).merge!({
        "gh.repo.path" => body.path,
        "gh.repo.name_with_owner" => body.repo,
        "gh.actor.id" => actor_id(commit_refs.actor),
        "gh.actor.type" => commit_refs.actor&.class&.name
      })

      Failbot.push(
        "gh.actor.id": actor_id(commit_refs.actor),
        "gh.actor.type": commit_refs.actor&.class&.name,
      )

      commit_refs.process
    rescue => e # rubocop:todo Lint/GenericRescue
      ref_results = {}
      if body && body.refs
        body.refs.each do |ref, _before, _after|
          ref_results[ref] = "failure"
        end
      end

      err =
        if GitHub.global_operator_mode_enabled? || (commit_refs&.git_sockstat && commit_refs.git_sockstat.value("user_operator_mode"))
          "fatal error in commit_refs: %s\n" % e.inspect + "\n" + e.backtrace.inspect
        else
          "fatal error in commit_refs\n"
        end

      # Note that a reason value of "unknown" or any unknown value will be
      # treated like an error (that is, GitHub-caused) in babeld rather than as
      # a failure (that is, user-caused).  If you add a new type of failure,
      # please add it to babeld as well.
      reason = e.try(:commit_refs_reason) || "unknown"

      response = {
        "ok"     => false,
        "err"    => err,
        "refs"   => ref_results,
        "reason" => reason,
      }

      log_exception(request, e, {
        "code.function" => __method__,
        "rpc.method" => "commit-refs",
        "gh.repo.path" => body&.path,
        "gh.repo.name_with_owner" => body&.repo,
        "gh.actor.id" => actor_id(commit_refs&.actor),
        "gh.actor.type" => commit_refs&.actor&.class&.name
      })

      Failbot.report(e) unless e.is_a? GitHub::DGit::ThreepcBusyError

      response
    end

    # Internal: Filter member if it appears to be an OAuth token or deploy key.
    #
    # Users may pass an OauthAccess token using basic auth as their username or
    # their password (we accept both). We check to seee if `member` looks like
    # an OauthAccess token (40 hex chars) so that it can be safely filtered in
    # the logs.
    #
    # Deploy keys are represented by the repo ID and name with owner. The repo
    # name also needs to be sanitized before it can be passed on to external
    # logging tools.
    #
    # member - The String member that may contain a user login, OAuth
    #          token, or other representation of the actor performing
    #          the operation.
    #
    # Returns the filtered member as a String.
    def self.filtered_member(member)
      if OauthAccess.matches_pattern?(member)
        # legacy PATs, oauth app tokens,  GitHub app u2s
        FILTERED
      elsif GitHub.auth.authnd_token?(member)
        # FG PATs (PATs v2)
        FILTERED
      elsif member.to_s.start_with?("repo")
        member.split(":")[0..1].join(":")
      else
        member
      end
    end
    private_class_method :filtered_member

    # Rack application for serving permissions requests. This is mounted into
    # config.ru at /_gitauth and expects the following query parameters:
    #
    # path - The logical user, wiki, or gist repository path. The
    #   ".git" extension must be included.
    # member - The string username (or repository name in case of deploy key) of
    #   the account requesting access.
    # action - The requested access level. Must be either 'read' or 'write'.
    # proto - The protocol of the request
    # dc - The datacenter from which the original request was sent.  Used to
    #   sort the results of route lookups to prefer that datacenter.
    #
    # Returns a 200 response with the "<host>:<path>" of the physical repository
    #   when access is granted. If access is not available for any reason, a 403
    #   response is returned with an error message for the user in the body.
    def self.handle_request(request)
      request_id = Rack::RequestId.get(request.env)

      params  = request.POST

      action              = params["action"]
      fingerprint_sha256  = params["fingerprint_sha256"]
      hostname            = params["hostname"]
      key                 = params["key"]
      password            = params["password"]&.b # passwords can contain random chars
      path                = params["path"]
      protocol            = params["proto"] || (password.nil? ? "ssh" : "http")
      svnbridge_mode      = params["slumlord"] == "true" # svn requests formerly known as slumlord
      sigtype             = params["sigtype"]

      repo = path.to_s.chomp(".git") if path

      member = parse_member(params["member"], svnbridge_mode)
      filtered_member = filtered_member(member)
      request_access_security_header = request.env["HTTP_SEC_GITHUB_ALLOWED_ENTERPRISE"]

      cache_enabled = cache_enabled?(path, action, member)

      failbot_context = {
        "rpc.method": action,
        "gh.gitauth.fingerprint_sha256": fingerprint_sha256,
        "gh.gitauth.key": key,
        "host.name": hostname,
        "gh.gitauth.member": filtered_member,
        "network.protocol.name": protocol,
        "gh.request_id": request_id,
        "gh.gitauth.svnbridge_mode": svnbridge_mode,
        "gh.gitauth.sigtype": sigtype,
        "gh.gitauth.request_access_security_header": request_access_security_header,
        "gh.gitauth.cache.enabled": cache_enabled,
      }
      Failbot.push(failbot_context)

      log_data(request).merge!({
        "rpc.method" => action,
        "gh.repo.path" => path,
        "gh.repo.name_with_owner" => repo,
        "network.protocol.name" => protocol,
        "gh.gitauth.key" => key,
        "gh.gitauth.fingerprint_sha256" => fingerprint_sha256,
        "host.name" => hostname,
        "gh.gitauth.member" => filtered_member,
        "gh.gitauth.sigtype" => sigtype,
        "gh.gitauth.request_access_security_header" => request_access_security_header,
        "gh.gitauth.cache.enabled" => cache_enabled,
      }.reject { |_k, v| v.nil? })

      span = self.rack_span
      span.add_attributes("rpc.method" => action, "network.protocol.name" => protocol)

      response = T.let("", String)
      status = T.let(:not_ok, Symbol)
      cacheable_result = T.let(nil, T.untyped)
      from_cache = T.let(false, T::Boolean)
      permissions = T.let(nil, T.nilable(GitAuth::Access))
      case action
      when "verify-key"
        # This action identifies an SSH key and maps it to an actor.
        #
        # Only after this step has succeeded might a given SSH key be
        # subsequently used together with `verification-token`,
        # `git-lfs-authenticate`, or the default action below.
        # It could also be used alone, in the case of calling
        # `ssh -T`.
        #
        # IMPORTANT - However, this action is also cached on babeld's side of things
        # as an optimization. So, it's important to keep in mind that this may not
        # _always_ be called before the subsequent actions mentioned above.
        status, response = GitAuth::Metrics.time("handle_request", tags: ["action:#{action}"]) do
          self.verify_key_with_experiment(request)
        end
      when "verification-token"
        GitAuth::Metrics.time("handle_request", tags: ["action:#{action}"]) do
          # This action is used with `ssh git@github.com verify`.
          #
          # This generates a token that the user can send to support
          # in the case where they've lost access to their 2FA device
          # or verification mechanisms.
          # Support then disables 2FA on their account, and the user
          # can set up 2FA fresh with a new device.
          # See https://saga.githubapp.com/docs/general/security/identity-verification.html#ssh-verification
          if member == :anonymous
            # TODO: investigate.
            # We don't return an error message for anonymous requests.
            # Is this intentional?
            response = "\n"
          else
            response = "#{GitHub::SshVerification.generate_token(member, fingerprint_sha256) || "Error generating token."}\n"
          end
          # TODO: investigate.
          # We return :ok, whether the response succeeded or not.
          # Is this intentional?
          status = :ok
        end
      when "git-lfs-authenticate"
        GitAuth::Metrics.time("handle_request", tags: ["action:#{action}"]) do
          # This action generates a token for GitLFS access.
          #
          # It is only used with the SSH protocol, and
          # the resulting token is passed with the Authentication
          # header to an HTTPS request.
          status, response = git_lfs_authenticate(
            lfs_args: params["lfs-args"],
            path: path,
            member: member,
            protocol: protocol,
            password: password,
            key: key,
            ip: request.ip,
            country: request.env["HTTP_X_COUNTRY"],
            original_user_agent: request.env["HTTP_X_ORIGINAL_USER_AGENT"],
            req_id: request_id,
            sigtype: sigtype,
            request_access_security_header: request_access_security_header,
          )

          GitHub.dogstats.increment("lfs.ssh_resp", tags: ["status:#{status}"])
        end
      else
        # This default action is used to determine whether the actor may
        # perform a particular git operation.

        cached_result = fetch_cached_result(request, action, member, repo) if cache_enabled
        GitAuth::Metrics.time("handle_request", tags: ["action:#{action}", "cached_result:#{cached_result.present? ? "hit" : "miss"}"]) do
          result = if cached_result.present?
            from_cache = true
            status = T.let(cached_result[:auth_status], Symbol)

            GitHub.dogstats.increment("git", tags: ["source:gitauth", "type:#{protocol}", "action:#{action}", "status:#{status}"])

            if cached_result[:result].is_a?(Hash)
              stats = {}
              stats[:frontend] = Socket.gethostname
              stats[:real_ip] = request.ip
              stats[:frontend_pid] = Process.pid
              stats[:frontend_ppid] = Process.ppid
              stats[:committer_date] = Time.now.strftime("%s %z")
              stats[:hostname] = GitHub.host_name

              cached_stats = stats.merge(cached_result[:result][:stats] || {})

              {
                stats: cached_stats,
                routes: cached_result[:result][:routes],
                audit_log_pack_kvs: cached_result[:result][:audit_log_kv],
                commit_refs_pack_ctx: commit_refs_pack_ctx(cached_stats, svnbridge_mode, nil),
                postrx_hook_ctx: cached_result[:result][:postrx_hook_ctx],
              }
            else
              cached_result[:result]
            end
          end

          result = if result.present?
            result
          else
            args = {
              path: path,
              ip: request.ip,
              country: request.env["HTTP_X_COUNTRY"],
              original_user_agent: request.env["HTTP_X_ORIGINAL_USER_AGENT"],
              request_id: request_id,
              member: member,
              action: action,
              protocol: protocol,
              key: key,
              password: password,
              sigtype: sigtype,
              request_access_security_header: request_access_security_header,
            }

            permissions = GitAuth::Access.new(**args)
            status, response = permissions.verify
            stats = permissions.stats
            extend_log_request_for(request, permissions.user, stats)

            tags = ["action:#{action}"]
            member_type, * = stats[:member]&.split(":")
            credential_type, * = stats[:credential]&.split(":")
            tags << "member_type:#{member_type || 'unknown'}"
            tags << "credential_type:#{credential_type || 'unknown'}"
            tags << "protocol:#{protocol}"
            tags << "result:#{status}"

            if status == :ok
              # These are only set on successful authentication.
              log_data(request)["gh.gitauth.filtered_member"] = stats[:filtered_member]
              log_data(request)["gh.gitauth.credential"] = stats[:credential]
            end

            GitHub.dogstats.increment("gitauth.authentication", tags: tags)

            if status == :not_ip_allowlisted
              log_data(request).merge!({
                "gh.ip_allow_list.policy_unsatisfied" => true,
                "gh.ip_allow_list.policy_evaluated.ip" => request.ip,
                "gh.ip_allow_list.policy_owner.id" => permissions.target.repository.owner.id,
                "gh.ip_allow_list.policy_owner.type" => :ORG
              })
            end

            if status == :ok
              _, shard = response.split(/:/)
              target = permissions.target

              audit_log_only_stats = {}
              if permissions.authentication&.token
                audit_log_only_stats = { token: permissions.authentication&.token }
              end

              {
                routes: target.routes(shard, protocol, action),
                stats:,
                audit_log_pack_kvs: audit_log_pack_kvs(target, stats.merge(audit_log_only_stats)),
                commit_refs_pack_ctx: commit_refs_pack_ctx(stats, svnbridge_mode, member_auth_type(permissions.user)),
                postrx_hook_ctx: {
                  "url"    => target.postrx_hook_url,
                  # Use the user login for the pusher if available. Otherwise use the SSH key verifier.
                  "pusher" => stats.values_at(:user_login, :pubkey_verifier_login).compact.first.to_s,
                }
              }
            else
              response
            end
          end

          if result.is_a?(Hash)
            response = {
              "routes"          => result[:routes],
              "intercept"       => "repl", # Setting intercept=repl tells babeld to hit /_commit_refs.
              "sockstat"        => GitHub::GitSockstat.format(result[:stats]),
              "audit_log_kv"    => result[:audit_log_pack_kvs],
              "commit_ref_ctx"  => result[:commit_refs_pack_ctx],
              "postrx_hook_ctx" => result[:postrx_hook_ctx],
            }.to_json
          else
            response = result
          end

          cacheable_result = result
        end
      end

      reply_json = request.env["HTTP_ACCEPT"] == "application/json"

      # On success we already return JSON with all the information, but on any
      # kind of error, we need to make our response wrap the auth status and
      # error message in JSON
      if reply_json && status != :ok
        response = {
          auth_status: status,
          body: response
        }.to_json
      end

      headers = {
        "Content-Length" => response.bytesize.to_s,
        "Content-Type" => reply_json ? "application/json" : "text/plain",
      }
      headers["X-GitHub-Request-Id"] = request_id unless request_id.nil?
      headers["X-GitHub-Tenant"] = GitHub::CurrentTenant.get&.slug if set_tenant_header?

      log_data(request)["gh.gitauth.status"] = status

      result = case status
      when :ok
        [200, headers, [response]]
      when :ldap_timeout
        # Terminate the worker in the event of an LDAP timeout to prevent any
        # inconsistencies that may occur due to the timeout.
        Process.kill("QUIT", Process.pid)
        [504, headers, [response]]
      when :auth_error, :git_with_password_auth, :weak_password
        # We return 401 for these cases to ensure that any credential managers don't continue supplying bad credentials
        # :auth_error is the genric case for username/password failure
        [401, headers, [response]]
      when :unauthorized_access_to_private_repository
        repository = permissions&.target&.repository

        business = Business.enterprise_managed_business_for(resource: repository) if protocol == "http" && repository.is_a?(Repository)
        if business&.sso_redirect_enabled? && business.shortcode
          redirect_hint = "#{business.slug}:#{business.shortcode}"

          headers["X-GitHub-Enterprise-Redirect"] = redirect_hint
          log_data(request)["gh.gitauth.enterprise_redirect_hint"] = redirect_hint

          ##
          # We do not cache responses with enterprise redirects as lookups for the business and the repository
          # are required for each request.
          #
          return [401, headers, [response]]
        else
          [403, headers, [response]]
        end
      else
        [403, headers, [response]]
      end

      cache_result(action, member, repo, result[0], status, headers, cacheable_result) if cache_enabled && !from_cache

      result
    rescue StandardError, Scientist::Experiment::MismatchError => boom # rubocop:todo Lint/GenericRescue
      printable_params = params.delete_if { |k, _| k == "password" }
      if printable_params.include? "refs"
        printable_params["refs"] = "<#{printable_params["refs"].count} refs>"
      end

      log_exception(request, boom, {
        "code.function" => __method__,
        "gh.gitauth.params" => printable_params.inspect,
        "gh.repo.path" => path,
        "gh.repo.name_with_owner" => path.to_s.chomp(".git"),
        "gh.gitauth.member" => filtered_member,
        "rpc.method" => action,
        "gh.gitauth.status" => status,
      })

      Failbot.report(boom, { "gh.gitauth.status": status })
      [500, {}, []]
    end

    def self.cache_result(action, member, repo, http_status, auth_status, headers, result)
      return if result.nil?
      return if auth_status == :ldap_timeout || auth_status == :missing

      cache_ttl = 5.seconds
      cached_result = {
        ##
        # Skip caching of the HTTP statuses for enterprise redirects to ensure that the proper headers are generated
        # for cached responses. We re-use the http_status field to eliminate the need for storing additional
        # data in the cache.
        #
        http_status:,
        auth_status:,
        result: if result.is_a?(Hash)
                  result.except(:stats).merge({
                    stats: result[:stats].except(:frontend, :real_ip, :frontend_pid, :frontend_ppid, :committer_date, :hostname)
                  })
                else
                  result
                end
      }

      GitHub.cache.set(cache_key(action, member, repo), cached_result, cache_ttl)
    end

    def self.fetch_cached_result(request, action, member, repo)
      cache_key = cache_key(action, member, repo)
      cached_result = GitHub.cache.get(cache_key) unless cache_key.nil?
      log_data(request)["gh.gitauth.cache.hit"] = !cached_result.nil?

      cache_status = cached_result.nil? ? "miss" : "hit"
      GitHub.dogstats.increment("gitauth.response_cache", tags: ["result:#{cache_status}"])

      return nil if cached_result.nil?
      return nil unless GitHub.flipper[:gitauth_use_response_cache].enabled?

      log_data(request)["gh.gitauth.cache.use"] = true

      if cached_result[:auth_status] == :ok || cached_result[:http_status] == 200
        target = GitAuth::Target.new("#{repo}.git")

        # If a repository has been deleted or is no longer private, we evict the cached result. Gists can not be made private
        # once they are marked as public. Private gists are also always accessible by anyone.
        if target.repository.nil? || (!target.gist? && target.repository&.respond_to?(:public?) && !target.repository.public?)
          GitHub.cache.delete(cache_key)
          log_data(request)["gh.gitauth.cache.evicted"] = true
          return nil
        end
      end

      cached_result
    end

    def self.cache_enabled?(path, action, member)
      return false if GitHub.enterprise?
      return false unless member == :anonymous
      return false if path.nil?
      return false unless %w[read write].include?(action)

      GitHub.flipper[:gitauth_set_response_cache].enabled?
    end

    def self.cache_key(action, member, repo)
      return nil if action.nil? || member.nil? || repo.nil?

      "gitauth:#{action}:#{member}:#{repo}"
    end

    def self.parse_member(member, svnbridge_mode)
      if member && !member.valid_encoding?
        member = member.b
      end
      member ||= svnbridge_mode ? :slumlord : :anonymous
    end

    def self.git_lfs_authenticate(lfs_args:, path:, member:, protocol:, password:, key:, ip:, country:, original_user_agent:, req_id:, sigtype:, request_access_security_header:)
      command, nwo, operation, _ = lfs_args.split(" ", 4)
      if command != "git-lfs-authenticate"
        return [:invalid_command, "Invalid command: #{command.inspect}"]
      end

      nwo = nwo[1..-1] if nwo[0] == "/"
      if path != nwo && path != "#{nwo}.git"
        return [:path_mismatch, "Repository path mismatch: #{nwo.inspect} vs #{path.inspect}"]
      end

      if !operation.in? %w(upload download)
        return [:invalid_operation, "Invalid LFS operation: #{operation.inspect}"]
      end

      action = operation == "upload" ? :write : :read
      args = {
        path: path,
        ip: ip,
        country: country,
        original_user_agent: original_user_agent,
        request_id: req_id,
        member: member,
        action: action,
        protocol: protocol,
        key: key,
        password: password,
        sigtype: sigtype,
        request_access_security_header: request_access_security_header,
      }
      permissions = GitAuth::Access.new(**args)
      if permissions.target.gist?
        return [:bad_permissions, "LFS cannot be used on Gist repositories"]
      end
      status, msg = permissions.verify
      return [:bad_permissions, msg] if status != :ok

      lfs_auth = GitAuth::GitLFS.new(
        operation: operation,
        repository: permissions.target.repository,
        actor: permissions.user,
        deploy_key: permissions.user.nil? ? permissions.public_key : nil,
        protocol: protocol,
      )

      json = GitHub::JSON.encode(lfs_auth.response, pretty: true).to_s

      # Protects us from overflowing babeld buffer
      # https://github.com/github/babeld/pull/310#discussion-diff-26442959
      if json.size > 512
        return [:invalid_json, "JSON output too large"]
      end

      [:ok, json]
    end

    # SAFELY DEPLOYING CHANGES:
    #
    # If changing the set of key-values returned here, ensure first that multiple
    # versions of babeld are able to consume both variations: the set of key-values
    # before your change, and after. Babeld clients will span multiple hosts and
    # may also span multiple versions.  Some changes may require to be staged over
    # multiple deploys.
    #
    # Populate the set of "audit_log_kv" key-values as returned to Gitauth clients.
    # These key-values are later propagated into the Audit Log system as part of
    # fulfilling git operations (fetches, pushes).
    #
    #   target - GitAuth::Target representing the repo, wiki, or gist at hand
    #
    #   stats - Ruby dictionary filled with various pre-queried information
    #           like repository name and relevant user login and ID, as populated
    #           with `GitAuth::Access#stats`.
    #
    def self.audit_log_pack_kvs(target, stats)
      result = {}

      result["repository"] = stats[:repo_name] || ""
      result["repository_id"] = stats[:repo_id] || 0
      result["repository_spec"] = stats[:repo_spec] || ""

      result["repository_owner"] = stats[:repo_owner_login] || ""
      result["repository_owner_id"] = stats[:repo_owner_id] || 0
      result["repository_owner_type"] = stats[:repo_owner_type] || ""

      result["actor"] = stats[:user_login] || ""
      result["actor_id"] = stats[:user_id] || 0
      result["actor_type"] = stats[:user_type] || ""

      result["user"] = ""
      result["user_id"] = 0

      result["pubkey_id"] = stats[:pubkey_id] || 0
      result["pubkey_verifier_id"] = stats[:pubkey_verifier_id] || 0
      result["pubkey_creator_id"] = stats[:pubkey_creator_id] || 0

      result["member"] = stats[:member] || ""
      result["credential"] = stats[:credential] || ""
      result["token_id"] = stats[:oauth_access_id] || stats[:user_programmatic_access_id] || 0
      result["token_type"] = stats[:credential]&.split(":")[1] || ""
      result["programmatic_access_type"] = Audit::AuthData.git_credential_type(stats[:credential] || "", stats.delete(:token) || "")

      result["request_access_security_header"] = stats[:request_access_security_header] || ""

      repo = target.repository
      if !target.gist? && repo.in_organization?
        org = repo.organization
        result["org"] = org.display_login
        result["org_id"] = org.id

        if org.business.present?
          business = org.business
          result["business"] = business.slug
          result["business_id"] = business.id
        end

        entity = business || org

        # attempt to gather the sso/saml authentication for this event

        # first we need the owner and the sso provider
        ei_session_owner = entity.external_identity_session_owner
        sso_enabled, async_provider = case ei_session_owner
        when Business
          [ei_session_owner.external_provider_enabled?, ei_session_owner.async_external_provider]
        when Organization
          [ei_session_owner.saml_sso_enabled?, ei_session_owner.async_saml_provider]
        end

        if sso_enabled && async_provider
          async_provider.then do |provider|
            if provider
              if result["actor_id"]&.nonzero? && result["actor_type"] == "User"
                actor = User.find_by(id: result["actor_id"])
                if actor
                  # with the provider we can get the actors external identity info
                  actor.external_identities.by_provider(provider).each do |ident|
                    result["external_identity_username"] = ident.user_name if ident.user_name.present?
                    result["external_identity_nameid"] = ident.name_id if ident.name_id.present?
                    result["external_id"] = ident.external_id if ident.external_id.present?
                    result["external_id"] ||= ident.saml_external_id if ident.saml_external_id.present?
                  end
                end
              end
            end
          end.sync
        end
      end

      if (!result["business_id"] || result["business_id"] == 0) && result["actor_id"]&.nonzero? && result["actor_type"] == "User"
        if business = User.find_by(id: result["actor_id"]).try(:enterprise_managed_business)
          result["business"] = business.slug
          result["business_id"] = business.id
        end
      end

      result
    end

    # SAFELY DEPLOYING CHANGES:
    #
    # If making changes here and in #commit_refs_actor_from_ctx please consider
    # deploying separately. Requests to _git_auth and _commit_refs may happen
    # on different hosts, with different deploys. So changes may need to be
    # staged over two deploys.
    def self.commit_refs_pack_ctx(stats, svnbridge_mode, auth_type)
      h = {}
      if stats.key?(:user_id)
        h["user_id"] = stats[:user_id]
        if GitHub.multi_tenant_enterprise?
          h["tenant"] = stats[:tenant]
        end
      elsif stats.key?(:pubkey_id)
        h["pubkey_id"] = stats[:pubkey_id]
      end
      if stats.key?(:oauth_access_id)
        h["oauth_access_id"] = stats[:oauth_access_id]
      end
      if stats.key?(:installation_id) && stats.key?(:installation_type)
        h["installation_id"] = stats[:installation_id]
        h["installation_type"] = stats[:installation_type]
      end
      if stats.key?(:user_programmatic_access_id)
        h["user_programmatic_access_id"] = stats[:user_programmatic_access_id]
      end
      h["slumlord"] = "true" if svnbridge_mode
      h["auth_type"] = auth_type if auth_type && !h.empty?
      h.to_json
    end

    class NoActorError < StandardError
    end

    # SAFELY DEPLOYING CHANGES:
    #
    # If making changes here and in #commit_refs_pack_ctx please consider
    # deploying separately. Requests to _git_auth and _commit_refs may happen
    # on different hosts, with different deploys. So changes may need to be
    # staged over two deploys.
    #
    # Returns an (actor, auth_type) pair.
    def self.commit_refs_actor_from_ctx(ctx_json)
      ctx = GitHub::JSON.parse(ctx_json)
      auth_type = ctx.key?("auth_type") && ctx["auth_type"].to_sym

      if auth_type == :bot && ctx.key?("installation_id") && ctx.key?("installation_type")
        # Fetching the Bot through the IntegrationInstallation or
        # ScopedIntegrationInstallation hydrates it with the repository
        # installation which is the abilities delegate.
        installation =
          case ctx["installation_type"]
          when "IntegrationInstallation"
            IntegrationInstallation.find(ctx["installation_id"].to_i)
          when "ScopedIntegrationInstallation"
            ScopedIntegrationInstallation.find(ctx["installation_id"].to_i)
          when "SiteScopedIntegrationInstallation"
            SiteScopedIntegrationInstallation.find(ctx["installation_id"].to_i)
          end
        installation.bot
      elsif ctx.key?("user_id")
        user = User.find(ctx["user_id"].to_i)
        if ctx.key?("oauth_access_id")
          # Re-attach the oauth access that was used to authenticate so that we
          # can check the scopes used later in RefUpdatesPolicy.
          user.oauth_access = OauthAccess.find(ctx["oauth_access_id"].to_i)
        elsif ctx.key?("user_programmatic_access_id")
          user.programmatic_access = ProgrammaticAccess.find(ctx["user_programmatic_access_id"].to_i)
        end
        user
      elsif ctx.key?("pubkey_id")
        PublicKey.find(ctx["pubkey_id"].to_i)
      elsif ctx.key?("slumlord") && ctx["slumlord"] == "true"
        :slumlord
      else
        Failbot.push({
          "gh.gitauth.type": ctx["auth_type"],
          "gh.installation.type": ctx["installation_type"],
          "gh.installation.id": ctx["installation_id"],
          "gh.user.id": ctx["user_id"],
          "gh.oauth.access.id": ctx["oauth_access_id"],
          "gh.user_programmatic_access.id": ctx["user_programmatic_access_id"],
          "gh.public_key.id": ctx["pubkey_id"],
          "gh.gitauth.svnbridge_mode": ctx["slumlord"]
        })
        raise NoActorError, "context missing installation_id, installation_type, user_id and pubkey_id"
      end
    rescue ActiveRecord::RecordNotFound
      Failbot.push({
        "gh.gitauth.type": ctx["auth_type"],
        "gh.installation.type": ctx["installation_type"],
        "gh.installation.id": ctx["installation_id"],
        "gh.user.id": ctx["user_id"],
        "gh.oauth.access.id": ctx["oauth_access_id"],
        "gh.user_programmatic_access.id": ctx["user_programmatic_access_id"],
        "gh.public_key.id": ctx["pubkey_id"],
        "gh.gitauth.svnbridge_mode": ctx["slumlord"]
      })
      raise NoActorError, "record was deleted before lookup could complete"
    end

    def self.actor_id(actor)
      actor.try(:id) || actor.try(:to_s)
    end

    def self.verify_key_with_experiment(request)
      science "gitauth.gotauth-verify-key" do |e|
        e.use do
          self.verify_key(request)
        end
        e.try do
          self.verify_key_gotauth(request)
        end
        e.compare do |control, candidate|
          control_status, control_response = control
          candidate_status, candidate_response = candidate

          control_status == candidate_status && control_response == candidate_response
        end
        e.run_if { GitHub.flipper[:gotauth_verify_key_experiment].enabled? }
      end
    end

    def self.verify_key(request)
      key, fingerprint_sha256, ssh_login = request.POST.fetch_values(
        "key",
        "fingerprint_sha256",
        "ssh_login",
      )

      org_id, tenant_slug = GitAuth::SSHLoginParser.parse(ssh_login)
      business_id = nil
      if GitHub.multi_tenant_enterprise?
        business = Business.find_by(slug: tenant_slug)
        GitHub::CurrentTenant.set(business)
        business_id = business&.id
      end

      if ssh_certificate?(key)
        verify_certificate(key, ip: request.ip, business_id: business_id, org_id: org_id)
      else
        verify_public_key(fingerprint_sha256, key, request.ip, business_id: business_id, org_id: org_id)
      end
    end

    sig { returns Faraday::Connection }
    def self.client_gotauth
      @gotauth_client ||= GitHub::FaradayClient::Internal.new(GitHub.gotauth_address) do |conn|
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: GOTAUTH_SERVICE_NAME
        conn.use GitHub::FaradayMiddleware::Retries, options: GitHub::FaradayClient::DEFAULT_RETRY_OPTIONS
        conn.use GitHub::FaradayMiddleware::Resilient, name: GOTAUTH_SERVICE_NAME, options: GitHub::FaradayClient::DEFAULT_RESILIENT_OPTIONS

        conn.options[:open_timeout] = 0.1 # 100ms
        conn.options[:timeout] = 0.5 # 500ms
        conn.request :url_encoded

        conn.adapter :persistent_excon
      end
    end

    def self.verify_key_gotauth(request)
      # Forward select headers
      headers = {
        "Accept" => request.env["HTTP_ACCEPT"],
        "Referer" => request.referer,
        "X-Forwarded-For" => request.env["HTTP_X_FORWARDED_FOR"],
      }

      resp = client_gotauth.post("/_gitauth", request.POST, headers)

      return [:ok, resp.body] if resp.status == 200

      result = begin
        JSON.parse(resp.body)
      rescue JSON::ParseError
        {}
      end

      status = (result["auth_status"] || :not_ok).to_sym
      response = result["body"] || ""

      [status, response]
    rescue Faraday::Error => e
      Failbot.report(e, app: "gotauth")
      [:not_ok, "Internal server error"]
    end

    # The return value is [result, message].
    #
    # The 'result' value is a symbol that is either :ok
    # or something else. The something else doesn't
    # actually matter, it's just for debugging purposes,
    # and logging to datadog.
    #
    # The 'message' value is returned to babeld in the response body
    def self.verify_public_key(fingerprint_sha256, key, ip, business_id:, org_id:)
      ssh_cert_required = ssh_certificate_requirement_enabled_for?(business_id: business_id, org_id: org_id)
      pubkey = GitAuth::SSHKey.with_fingerprint_sha256(fingerprint_sha256)

      if pubkey
        result, message = pubkey.verify(key, ssh_required: ssh_cert_required)
      else
        result  = :unknown_key
        message = "Unknown SSH Key"
      end

      [result, message]
    ensure
      tags = ["type:pubkey"]

      if pubkey
        key_type, * = pubkey.key&.split(" ")
        tags << "member_type:#{pubkey.type}"
        tags << "key_type:#{key_type || 'unknown'}"
      end

      tags << "result:#{result}"
      GitHub.dogstats.increment("gitauth.verify_key", tags: tags)
    end

    def self.ssh_certificate_requirement_enabled_for?(business_id:, org_id:)
      return false if business_id.nil? && org_id.nil?

      if org_id && business_id.nil?
        business_id = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(<<-SQL, org_id: org_id))
          SELECT business_id
          FROM business_organization_memberships
          WHERE organization_id=:org_id
        SQL
      end

      if business_id && org_id
        has_ca = ApplicationRecord::Collab.connection.select_value(Arel.sql(<<-SQL, org_id: org_id, business_id: business_id))
          SELECT 1
          FROM ssh_certificate_authorities
          WHERE (owner_type='Business' AND owner_id=:business_id)
            OR (owner_type='User' AND owner_id=:org_id)
          LIMIT 1
        SQL
      elsif business_id
        has_ca = ApplicationRecord::Collab.connection.select_value(Arel.sql(<<-SQL, business_id: business_id))
          SELECT 1
          FROM ssh_certificate_authorities
          WHERE owner_type='Business' AND owner_id=:business_id
          LIMIT 1
        SQL
      elsif org_id
        has_ca = ApplicationRecord::Collab.connection.select_value(Arel.sql(<<-SQL, org_id: org_id))
          SELECT 1
          FROM ssh_certificate_authorities
          WHERE owner_type='User' AND owner_id=:org_id
          LIMIT 1
        SQL
      end

      return false unless has_ca

      if business_id && org_id
        rows = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, org_id: org_id, business_id: business_id)).to_a
          SELECT name, value, final,
          CASE target_type
          WHEN 'global'     THEN 0
          WHEN 'Business'   THEN 1
          WHEN 'User'       THEN 2
          END AS priority
          FROM configuration_entries
          WHERE (
            (target_type='global' AND target_id=0)
              OR
            (target_type='User' AND target_id=:org_id)
              OR
            (target_type='Business' AND target_id=:business_id)
          ) AND (
            name IN ('ssh_enabled', 'ssh_certificate_requirement')
          )
          ORDER BY priority
        SQL
      elsif business_id
        rows = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, business_id: business_id)).to_a
          SELECT name, value, final,
          CASE target_type
          WHEN 'global'     THEN 0
          WHEN 'Business'   THEN 1
          END AS priority
          FROM configuration_entries
          WHERE (
            (target_type='global' AND target_id=0)
            OR
            (target_type='Business' AND target_id=:business_id)
          ) AND (
            name IN ('ssh_enabled', 'ssh_certificate_requirement')
          )
          ORDER BY priority
        SQL
      elsif org_id
        rows = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, org_id: org_id)).to_a
          SELECT name, value, final,
          CASE target_type
          WHEN 'global'     THEN 0
          WHEN 'User'       THEN 1
          END AS priority
          FROM configuration_entries
          WHERE (
            (target_type='global' AND target_id=0)
              OR
            (target_type='User' AND target_id=:org_id)
          ) AND (
            name IN ('ssh_enabled', 'ssh_certificate_requirement')
          )
          ORDER BY priority
        SQL
      end

      entries = {}
      rows.each do |row|
        current = entries[row["name"]]
        next if current && [1, "1", true].include?(current["final"])
        entries[row["name"]] = row
      end
      config = entries.each_with_object({}) do |(name, row), config|
        config[name] = row["value"]
      end

      ssh_enabled = config["ssh_enabled"] != "false" # defaults to true
      cert_required = config["ssh_certificate_requirement"] == "true" # defaults to false

      ssh_enabled && cert_required
    end

    def self.verify_certificate(key, business_id:, org_id:, ip:)
      result, user_id, user_login, user_display_login, ca = GitAuth::SSHCertificateAuthority.validate_certificate(key,
        ip: ip,
      )

      # if the result was OK (meaning the certificate is valid)
      # check to see if we can also verify the certificate is owned by the org or business
      # the user is trying to access
      # if business_id and org_id are both nil, we can't check here - it'll be checked later in the SSH handshake
      if result == :ok
        if org_id
          org_exists = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(<<-SQL, org_id: org_id))
            SELECT 1
            FROM users
            WHERE id=:org_id
            AND type='Organization'
          SQL
          # We got a hint that the user is trying to access a repo belonging to
          # an org, so we verify that the CA is usable by that org.
          if org_exists && !ca.owned_by_organization_or_associated_business?(org_id)
            result = :wrong_ca
          end
        elsif business_id
          # We got a hint that the user is trying to access a repo belonging to
          # a business, so we verify that the CA is usable by that business.
          if !ca.owned_by_business?(business_id)
            result = :wrong_ca
          end
        end
      end

      GitHub.dogstats.increment("gitauth.verify_key", tags: [
        "type:cert",
        "result:#{result}",
      ])

      if result == :ok
        [:ok, "user:#{user_id}:#{user_display_login}"]
      else
        [:not_ok, "ssh_cert_#{result}"]
      end
    end

    def self.ssh_certificate?(key)
      return false if key.nil?
      algo, _, _ = SSHData.key_parts(key)
      SSHData::Certificate::ALGOS.include?(algo)
    rescue SSHData::Error => e
      Failbot.report(e)
      false
    end

    def self.initial_context(request)
      {
        actor_ip: request.ip,
        catalog_service: SERVICE_NAME,
        from: "GitHub::RepoPermissions",
        request_id: Rack::RequestId.get(request.env),
        server_id: Rack::ServerId.get(request.env),
        url: request_url(request),
        method: request.try(:request_method),
      }
    end

    def self.extend_log_request_for(request, user, stats)
      return unless user.present?

      # logging for programmatic actors added for https://github.com/github/ecosystem-apps/issues/3282
      # previously only server-to-server requests were logged
      # `gh.user.id` was renamed to `gh.actor.id`
      programmatic_actor_data = { "gh.actor.id" => stats[:user_id] }

      if user.bot?
        # tracking for server-to-server requests. REF https://github.com/github/ecosystem-apps/issues/1339
        programmatic_actor_data.merge!({
          "gh.installation.id" => stats[:installation_id],
          "gh.installation.type" => stats[:installation_type],
          "gh.installation.created_at" => stats[:installation_created_at],
          "gh.integration.id" => stats[:integration_id],
          "gh.installation.expires_at" => stats[:installation_expires_at]
        })
      end

      programmatic_actor_data["gh.user_programmatic_access.id"] = stats[:user_programmatic_access_id]
      programmatic_actor_data["gh.oauth.access.id"] = stats[:oauth_access_id]

      log_data(request).merge!(programmatic_actor_data)
    end
    private_class_method :extend_log_request_for

    # The absolute URL for a request.
    #
    # Returns a String or nil.
    def self.request_url(request)
      begin
        "#{request.scheme}://#{request.host_with_port}#{request.fullpath}"
      rescue NoMethodError
      end
    end

    def self.rack_span
      # In almost all conditions our rack app should be called with tracer
      # middleware that sets up a span for the request. In cases where we
      # don't (like in tests), we provide this interface so we can have a
      # default.
      OpenTelemetry::Instrumentation::Rack.current_span
    end

    # Checks if the tenant header should be set for the current request.
    #
    # Returns Boolean
    def self.set_tenant_header?
      return false unless GitHub.multi_tenant_enterprise?
      GitHub::CurrentTenant.get.present?
    end
  end
end
