# typed: true
# frozen_string_literal: true

require "forwardable"

module GitAuth
  # Figure out whether the actor is allowed to perform the given git operation
  # on the repository at `path`.
  class Access
    include Scientist
    extend Forwardable
    include GitHub::Tracing

    attr_reader :action, :cap_results, :country, :credential, :full_member, :filtered_member, :key, :member, :password, :protocol, :ip, :target, :original_user_agent, :request_id, :sigtype, :status, :token, :request_access_security_header

    def_delegators :authentication, :user, :public_key

    # Verify member access to the repository to perform action. This includes
    # all the checks provided by the #check method.
    #
    # path       - the path to the repository.
    #              - "<user>/<repo>.git" for normal user repositories.
    #              - "<user>/<repo>.wiki.git" for wiki repositories.
    #              - "<gist-id>.git" or "gist/<gist-id>.git" for gists.
    # ip         - The IP address that permissions check is coming from.
    # member     - String username, "<user>/<repo>" deploy key,
    #              "user:<id>", or "repo:<id>" deploy key strings to test. May be
    #              nil or :anonymous to indicate anonymous access. May be
    #              :slumlord to indicate slumlord access.
    # action     - Either :read or :write.
    # protocol   - The protocol access is being requested from. Must be one of
    #              http, git, ssh, or svn.
    # country    - The country that the request is being made from.
    # key        - The SSH public key used to authenticate.
    # password   - The user's password.
    # original_user_agent - The requesting useragent (typically the client's git version)
    # request_id  - The request identifier, allowing us to log actions that stem
    #              from the same request.
    # sigtype    - The signature algorithm for SSH (e.g., rsa-sha2-512 or
    #              ssh-ed25519)
    def initialize(path:, ip:, member:, action:, protocol:, country: nil, key: nil, password: nil, original_user_agent: nil, request_id: nil, sigtype: nil, request_access_security_header: nil)
      @target     = GitAuth::Target.new(path)
      @ip         = ip
      @member     = member
      @action     = action.to_sym
      @protocol   = protocol
      @country    = country
      @original_user_agent = original_user_agent
      @request_id = request_id
      @key        = key
      @password   = password
      @sigtype    = sigtype
      @request_access_security_header = request_access_security_header
    end

    # Verify member access to the repository to perform action. This includes
    # all the checks provided by the #check method.
    def verify
      GitAuth::Metrics.time("access.verify") do
        validate_inputs

        @status = verify_instance
        @status ||= verify_target

        # Batch load configuration for optimization
        preload_configuration

        # First authenticate.
        result = authentication.process unless status
        @status = authentication.status if authentication.failed?

        # Then authorize.
        @status ||= authorization.check
        @status ||= :missing

        # Fetch all cap results
        # This is only used for comparing CAP results between gotauth and gitauth
        # It is not used for any authorization decisions
        @cap_results = authorization.cap_results

        begin
          if status == :ok
            if result
              @credential = result.credential
              @full_member = result.full_member
              @filtered_member = result.filtered_member
              @token = result.token
            end

            # The `exist?` check requires an external call which is expensive and should be avoided when possible.
            # When we have a false negative (we don't return missing but a repo does not exist), babled will return a 503
            # After some experimentation, we found that for repos (not wikis), only checking repos created in the last day
            # covers almost all cases where the repo does not exist.
            missing = if target.wiki?
              !target.exist?
            else
              target.repository.created_at.after?(1.day.ago) && !target.exist?
            end

            if missing
              @status = :missing
            else
              # Return early for the happy path.
              return [status, "#{target.host}:#{target.full_path}"] if target.host
            end
          end
        rescue GitHub::DGit::NotFoundError, GitHub::DGit::UnroutedError
          @status = :missing
        ensure
          perform_bookkeeping
        end

        [status, failure.message]
      end
    end
    trace_method :verify

    def authentication
      return @authentication if @authentication

      inputs = {
        protocol: protocol,
        action: action,
        member: member,
        password: password,
        key: key,
        target: target,
        ip: ip,
        original_user_agent: original_user_agent,
        request_id: request_id,
        sigtype: sigtype,
        request_access_security_header: request_access_security_header,
      }
      @authentication = GitAuth::Pipeline.new(**inputs)
    end

    def authorization
      @authorization ||= GitAuth::Authorization.new(target: target, authentication: authentication)
    end

    # Hash of stats about the context of the permissions request. These are
    # relayed through the different git protocols stacks so they're available to
    # hooks and monitor programs.
    def stats
      stats = {}
      stats[:frontend] = Socket.gethostname
      stats[:real_ip] = ip
      stats[:frontend_pid] = Process.pid
      stats[:frontend_ppid] = Process.ppid
      stats[:committer_date] = Time.now.strftime("%s %z")
      stats[:hostname] = GitHub.host_name
      stats[:request_access_security_header] = request_access_security_header

      if GitHub.multi_tenant_enterprise?
        stats[:business_id] = GitHub::CurrentTenant.get&.id
        stats[:tenant] = GitHub::CurrentTenant.get&.slug
        stats[:githooks_api_url_with_tenant] = GitHub.githooks_api_url
      end

      if repository
        stats[:repo_id] = repository.id
        stats[:repo_type] = spokes_repo_type
        stats[:repo_public] = repository.public? if repository.respond_to?(:public?)
        stats[:repo_name] = "gist/#{repository.gist_id}" if repository.respond_to?(:gist_id)
        stats[:repo_name] = repository.name_with_display_owner if repository.respond_to?(:name_with_display_owner)
        stats[:repo_redirect] = target.redirected_from if target.redirected?

        stats[:repo_config] = configuration.to_json

        stats[:repo_owner_login] = repository.owner_display_login if repository.respond_to?(:owner_display_login)
        stats[:repo_owner_id] = repository.owner_id if repository.respond_to?(:owner_id)
        stats[:repo_owner_type] = repository.owner.type if repository.respond_to?(:owner) && repository.owner

        stats[:repo_spec] = target.repository_spec if target.respond_to?(:repository_spec)

        if GitHub.anonymous_git_access_enabled? && repository.respond_to?(:anonymous_git_access_enabled?)
          stats[:repo_anonymous_access_enabled] = repository.anonymous_git_access_enabled?
        end

        if protocol == "svn" && GitHub.flipper[:svn_sunset].enabled?(repository)
          stats[:svn_enabled] = false
        end

        # Set the following stats only for pushes as they require potentially
        # expensive database calls or memcache queries that we prefer to omit
        # when not strictly necessary.
        if action == :write
          if repository.respond_to?(:has_pre_receive_hooks?) && repository.has_pre_receive_hooks?
            data = repository.pre_receive_hooks.to_json
            data_limit = GitHub::PreReceiveHookEntry::HOOK_STATS_LIMIT

            if data.bytesize > data_limit
              stats[:repo_pre_receive_hooks] = GitHub::PreReceiveHookEntry::OVERFLOW
            else
              stats[:repo_pre_receive_hooks] = data
            end
          end

          stats[:githooks_env] = GitHub.githooks_env
          stats[:large_blob_rejection_enabled] = GitHub.large_blob_rejection_enabled?
          stats[:maximum_ref_length] = GitHub.maximum_ref_length
          stats[:reject_sha_like_refs] = GitHub.reject_sha_like_refs?
          stats[:custom_hooks_dir] = GitHub.custom_hooks_dir
          stats[:support_link_text] = GitHub.support_link_text if GitHub.enterprise?
          stats[:lfs_integrity_max_oids] = GitHub.lfs_integrity_max_oids
          stats[:rails_env] = Rails.env
          stats[:is_enterprise] = GitHub.enterprise?
          stats[:is_multi_tenant_enterprise] = GitHub.multi_tenant_enterprise?
          if repository.respond_to?(:lfs_integrity_check_timeout)
            stats[:lfs_integrity_check_timeout] = repository.lfs_integrity_check_timeout
          end
          stats[:pre_receive_fallback_enabled] = true if GitHub.pre_receive_fallback_enabled?

          unless target.gist?
            # We only check the LFS integrity in repos that have at least one
            # Git LFS object successfully pushed to GitHub, and has not since
            # been deleted or archived. This way we avoid the scanning overhead
            # for the majority of repos that do not use Git LFS.
            #
            # This heuristic has a drawback:
            # If a repo has never successfully received a single Git LFS
            # object, then we would never scan it and never report the
            # error. That also means we would never scan a repo that uses
            # external Git LFS storage (e.g. Artifactory) which is good.
            #
            # This DB call is usually made right after new Media::Blobs have
            # been pushed. In order to reduce the risk of races we perform the
            # query explicitly not against the read-only replica.
            stats[:check_lfs_integrity] = Media::Blob.exists?(["repository_network_id = ? AND (state = ? OR state = ?)", repository.network_id, 1, 3])
          end

          # Increase the packedrefstimeout to 2s (default 1s)
          stats[:feature_set_packedrefstimeout] = true if GitHub.flipper[:set_packedrefstimeout].enabled?(repository)
        end

        # Advertise the tips of non-gist repositories part of a fork network.
        stats[:parent_repo_id] = repository.parent_id if repository.fork?

        # Pass through the different layers this feature flag to signal spokes-receive-pack the feature is enabled
        # This setting will indicate to spokes-receive-pack that it should use different pipes to perform the different
        # reference collection steps
        stats[:spokes_receive_pack_isolated_reference_discovery] = true if GitHub.flipper[:spokes_receive_pack_isolated_reference_discovery].enabled?(repository)

        # This flag marks git operations that are allowed to fail fast, which allows them to have a shorter delay
        # and return a faster 429 response to the client.
        if (FeatureFlag.vexi.enabled?(:gitop_fail_fast_mode, repository, default: false) ||
        (repository.respond_to?(:owner) && FeatureFlag.vexi.enabled?(:gitop_fail_fast_mode, repository.owner, default: false)))
          stats[:gitop_fail_fast_mode] = true
        end

        # This flag tells gitauth whether to publish the push hydro event that will kick off push processing in the monolith.
        # When this is set to true, babeld will not post to the internal pushes API for this push.
        stats[:self_enqueue_post_receive] = true

        if repository.respond_to?(:owner)
          # This flag tells spokes-receive-pack to adjust the push limit (through
          # receive.maxSize) up to 80GB.
          if action == :write && GitHub.flipper[:sockstat_show_is_importing].enabled?(repository.owner)
            stats[:is_importing] = ImportExport.domain.is_importing?(repository)
          else
            stats[:is_importing] = false
          end

          # This flag tells spokes-receive-pack to allow badDate fsck errors during migrations for Octoshift
          if action == :write && GitHub.flipper[:sockstat_allow_baddate_in_import].enabled?(repository.owner)
            stats[:allow_baddate_in_import] = ImportExport.domain.is_importing?(repository)
          else
            stats[:allow_baddate_in_import] = false
          end
        end
      end

      if user
        stats[:user_id] = user.id

        if user.type == "Bot"
          stats[:user_login] = user.login # rubocop:disable GitHub/DoNotAllowLogin
        else
          stats[:user_login] = user.display_login
        end

        stats[:user_type] = user.type
        stats[:user_operator_mode] = (user.has_operator_mode?(configuration) || GitHub.global_operator_mode_enabled?)

        # Classic PATs, OAuth, and GitHub Apps user-to-server
        if user&.oauth_access.present?
          stats[:oauth_access_id] = user.oauth_access.id
        end

        # Fine-grained PATs
        if user&.using_auth_via_user_programmatic_access?
          stats[:user_programmatic_access_id] = user.programmatic_access.id
        end

        # GitHub Apps server-to-server
        if user.respond_to?(:installation)
          if has_installation?(user)
            installation = user.installation
            stats[:installation_id] = installation.id
            stats[:installation_type] = installation.class.to_s
            stats[:integration_id] = installation.integration_id
            stats[:installation_created_at] = installation.created_at.utc.iso8601
            if installation.respond_to?(:expires_at) && installation.expires_at.present?
              stats[:installation_expires_at] = installation.expires_at.utc.iso8601
            end
          else
            # REF: https://github.com/github/ecosystem-apps/issues/1339#issuecomment-856101093
            stats[:installation_type] = "NullInstallation"
          end
        end

        if protocol == "svn"
          stats["user_author_name"] = user.git_author_name
          stats["user_author_email"] = user.git_author_email
          stats["user_time_zone"] = user.time_zone_name || "Etc/UTC"
        end
      end

      if public_key
        stats[:pubkey_id] = public_key.id
        stats[:pubkey_fingerprint] = public_key.fingerprint
        if (verifier = public_key.verifier) && verifier != user
          stats[:pubkey_verifier_id] = verifier.id
          stats[:pubkey_verifier_login] = verifier.display_login
        end
        if (creator = public_key.creator) && creator != verifier
          stats[:pubkey_creator_id] = creator.id
          stats[:pubkey_creator_login] = creator.display_login
        end
      end

      if authentication&.ssh_ca
        stats[:ssh_ca_id] = authentication.ssh_ca.id
        stats[:ssh_ca_owner_type] = authentication.ssh_ca.owner_type
        stats[:ssh_ca_owner_id] = authentication.ssh_ca.owner_id
      end

      # The possibilities for these two values are documented in the playbook at
      # https://ops.githubapp.com/docs/playbooks/gitauth.md.
      stats[:member] = @full_member if @full_member
      stats[:credential] = @credential if @credential
      # Same values as :member except without repo names and user logins
      stats[:filtered_member] = @filtered_member if @filtered_member

      stats["maintainer"] = true if authorization&.maintainer?

      unless repository.nil?
        stats["above_warn_quota"] = repository.above_warn_quota?
        stats["above_lock_quota"] = repository.above_lock_quota?
      end

      stats["quotas_enabled"] = GitHub.repository_quotas_enabled?
      stats["gitauth_version"] = GitHub.current_sha[0..7]

      if GitHub.spokes_receive?
        # Babeld will use spokes-receive-pack in place of git-receive-pack.
        stats["spokes_receive"] = true
        stats["spokes_quarantine"] = true

        # For writes, set a quarantine_id
        if protocol != "svn" && action == :write
          stats[:quarantine_id] = "ghq_#{SecureRandom.alphanumeric(11)}"
        end
      end

      stats
    end
    trace_method :stats

    private

    def spokes_repo_type
      case
      when target.normal_repo?
        "repo"
      when target.wiki?
        "wiki"
      when target.gist?
        "gist"
      end
    end

    def failure
      @failure ||= GitAuth::Failure.new(status: status, authentication: authentication, authorization: authorization, ssh_enabled: ssh_enabled?, country: country)
    end

    def validate_inputs
      if ![:read, :write].include?(action)
        raise ArgumentError, "action must be :read or :write"
      end

      if protocol == "ssh" && !member.to_s.start_with?("user:", "repo:")
        raise ArgumentError, "invalid member #{member.inspect} with SSH protocol"
      end

      if protocol != "ssh" && member.to_s.start_with?("user:", "repo:")
        raise ArgumentError, "invalid member #{member.inspect} with #{protocol} protocol"
      end

      if protocol == "git" && action == :write
        raise ArgumentError, "cannot write with git protocol"
      end

      if member == :slumlord && action == :read
        raise ArgumentError, "slumlord should only perform writes"
      end

      if member.to_s.start_with?("gitauth-full-trust:")
        raise ArgumentError, "potential injection attack: member #{member.inspect}"
      end

      if protocol == "ssh" && key.nil?
        raise ArgumentError, "ssh protocol must be used with an SSH key or certificate"
      end
    end

    def perform_bookkeeping
      unless public_key.nil?
        # Do some book-keeping to track that the key was used.
        PublicKey.access(id: public_key.id, last_accessed_at: public_key.accessed_at)
      end

      GitHub.dogstats.increment("git", tags: ["source:gitauth", "type:#{protocol}", "action:#{action}", "status:#{status}"])
      if status == :verified_email_required
        GitHub.dogstats.increment("git_access_blocked", tags: ["type:verified_email_required"])
      end
      if status == :ok && authorization&.maintainer?
        GitHub.dogstats.increment("git", tags: ["action:maintainer_pushed"])
      end
      if status == :ok && action == :write && public_key&.deploy_key?
        GitHub.dogstats.increment("git", tags: ["action:deploy_key_pushed"])
      end
    end

    def verify_instance
      # check for maintenance mode first, in which case we want to avoid any kind of
      # mysql or external service access entirely
      return :maintenance if maintenance_mode?

      if GitHub.enterprise? && action == :write && GitHub::Enterprise.license.expired?
        :license
      end
    end

    def verify_target
      return :invalid unless target.valid?
      return :gotauth_redirect if !repository.nil? && GitAuth::GotAuthFeatureFlags.is_redirect_enabled?(action.to_s, repository)
      return :ssh_disabled if protocol == "ssh" && !ssh_enabled?
      return :dmca if !repository.nil? && repository.access&.dmca?
      :country_block if !repository.nil? && repository.access&.country_block?(country)
    end

    # The configuration is always needed for `stats` and preloading it early allows us to avoid multiple
    # configuration calls
    def preload_configuration
      configuration if repository
    end

    def configuration
      @configuration ||= repo_config || default_config
    end

    def repo_config
      # Gists do not have a config object.
      if repository.respond_to?(:config)
        # Optimization: This sets the configuration on the repo, org, and business with a single configuration SQL call
        Configurable.preload_configuration([repository] + repository.configuration_owners)

        repository.config.to_hash
      end
    end

    def default_config
      GitHub.enterprise? ? GitHub.config.to_hash : {}
    end

    def ssh_enabled?
      configuration["ssh_enabled"].to_s != "false"
    end

    def repository
      target.repository
    end

    def maintenance_mode?
      File.exist?("#{Rails.root}/public/system/maintenance-git.html")
    end

    def has_installation?(user)
      user.installation.present?
    end
  end
end
