# typed: false
# frozen_string_literal: true

module GitHub
  # This object inits or forks a repo from a path.  It's used in Repository,
  # Gist, and GitHub::Unsullied wikis.
  class RepoCreator
    class LastSixMismatch < StandardError; end

    # Sets up for a new git repo to be created.
    #
    # object  - a Repository or Gist or GitHub::Unsullied::Wiki
    # options - Hash options:
    #           :host           - a String hostname
    #           :shard_path     - a String absolute path to create
    #           :public         - Boolean that enables or disables public repository access.
    #           :template       - String path from where to replicate hooks.
    #           :nwo            - String name_with_owner to write into info/nwo.
    #           :default_branch - String default branch name
    #           :initial_commit - Initial commit data to use when creating via Spokes.
    #
    # Returns RepoCreator instance.
    def initialize(object, options = {})
      @object = object
      @public   = options.delete(:public)
      @template = options[:template]
      @nwo = options.delete(:nwo)
      @default_branch = options.delete(:default_branch)
      @via_spokes = @object.is_a?(::Gist)
      @options = options
      @hash_algo = options[:hash_algo]

      @path = options.delete(:shard_path) || @object.original_shard_path
      @rpc = object.rpc
    end

    # Initializes a bare git repository using @path and @options.
    #
    # Returns true (legacy), or the spokes response
    def init
      if @via_spokes
        @object.spokes_api.create_repository(
          nwo: @nwo,
          default_branch: @default_branch,
          hash_algorithm: @hash_algo,
          initial_commit: @options[:initial_commit],
        )
      else
        ensure_initialized
        true
      end
    end

    # Forks a repo from the given parent repo.
    #
    # parent - The parent Repository instance.
    # head   - Optional String of the HEAD
    #
    # Returns nothing.
    def fork(parent, head = nil)
      Failbot.push("gh.repo.repo_creator.parent.id": parent.id, "gh.repo.repo_creator.parent.route": parent.route)

      if @via_spokes
        begin
          # Create repository via spokes, polling until completion
          token = T.let(token, T.nilable(GitHub::Spokes::Proto::Types::V1::Token))
          res = T.let(nil, T.nilable(GitHub::Spokes::Proto::Repositories::V1::CreateForkResponse))
          loop do
            res = parent.spokes_api.create_fork(
              fork_id: @object.id, branch_mode: :BRANCH_MODE_ALL_BRANCHES, nwo: @nwo, token: token, wait_milliseconds: 5000
            )
            token = res.token
            break if token.nil?
          end

          # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          if Rails.env.development? || Rails.env.test?
            # Update the orgin in the /config file to be identical
            # by default it includes the dgitN path which differs by replica & causes checksum mismatches
            @object.dgit_reload_routes!
            host = GitHub::DGit::Routing::hosts_for_gist(@object.id).first
            @object.rpc.config_store("remote.origin.url", "file://#{@object.original_shard_path}")

            if @object.is_a?(::Gist)
              GitHub::DGit::Maintenance.recompute_gist_checksums(@object, host)
            else
              GitHub::DGit::Maintenance.recompute_checksums(@object, host, is_wiki: false, force_dgit_init: true)
            end
            # we'll need to pretend this was successful when returning from this function
            res.status = :STATUS_COMPLETE
            res.message = ""
          end

          if res.status != :STATUS_COMPLETE
            Failbot.push("gh.repo.repo_creator.clone_operation_succeeded": false)
            fail "fork failed: #{res.message}"
          end
          @object.dgit_reload_routes!
          Failbot.push("gh.repo.repo_creator.clone_operation_succeeded": true)
        rescue GitHub::Spokes::ClientError, SpokesAPI::Error => e
          Failbot.push("gh.repo.repo_creator.clone_operation_succeeded": false)
          fail "fork failed: #{e.class.name} #{e.message}"
        end
      else
        # use local filesystem URL if on same machine to avoid network and
        # enable hard-links in new repository.
        path =
          if same_routes?(@object, parent)
            parent.shard_path
          else
            parent.internal_remote_url
          end

        Failbot.push "gh.repo.repo_creator.parent.host_path": path,
                      "gh.repo.repo_creator.parent.internal_remote_url": parent.internal_remote_url

        # Repos in DGit can't all clone to @path in test and development
        # environments, because they need to be cloning into three different
        # (replica) directories, and there's only one @path.  So this
        # workaround uses only the basename from @path, and clones into
        # whatever the @object's parent directory is.
        #
        # That's really only necessary for dev and test, but it's good to
        # run the same code in test that we run in prod.
        if !@object.is_a?(::Gist)
          parent_rpc = @object.network.parent_rpc
          basename = File.basename(@path)

          # sanity check: cloning to the basename only works if the rest of
          # the path is the same.  The "last six" here is the components
          # between the repository root and the actual repo dir, exclusive.
          # E.g., /data/repositories/c/nw/c4/ca/42/1/1.git
          #                          ^ ^^ ^^ ^^ ^^ ^
          path_last_six = File.dirname(@path).split("/").last(6)
          rpc_last_six = parent_rpc.backend.path.split("/").last(6)
          raise LastSixMismatch, "#{path_last_six.inspect} != #{rpc_last_six.inspect}" unless path_last_six == rpc_last_six

          parent_rpc.create_network_dir
          begin
            parent_rpc.bare_clone(path, basename)
          rescue GitRPC::CommandFailed => e
            fail "fork failed: #{e.class.name}"
          end
        else
          #
          # XXX: Figure out what to do for the non-dev case here:
          #      can't use the basename trick because different gists
          #      have different unrelated shard paths.  Each replica
          #      needs to have a different destination directory arg.
          #
          Failbot.push("gh.repo.repo_creator.all_write_routes": @rpc.backend.delegate.get_write_routes.map { |r| r.path }.join("\n"))
          @rpc.backend.delegate.get_write_routes.each do |r|
            gist_backend_rpc = r.build_maint_rpc
            Failbot.push("gh.repo.repo_creator.write_route_path": r.path)
            begin
              gist_backend_rpc.bare_clone(path, r.path)
              Failbot.push("gh.repo.repo_creator.clone_operation_succeeded": true)
            rescue GitRPC::CommandFailed => e
              Failbot.push("gh.repo.repo_creator.clone_operation_succeeded": false)
              fail "gist fork failed: #{e.class.name}"
            end
          end
        end
        if head && head != "master"
          @rpc.fs_write("HEAD", "ref: refs/heads/#{head}\n")
          # We don't update the DGit checksum here.  RepoCreator's callers do that.
        end
      end

      after_create
      true
    end

    # Boolean specifying whether the repository is public.
    def public?
      @public
    end

    # The opposite of public?.
    def private?
      !public?
    end

    # Tells the fileserver to make sure that the repo exists, that it has
    # the right hooks, the right initial branch (if specified), and that its
    # info/nwo has the right value.
    #
    # This is equivalent to doing:
    #
    #   @rpc.init
    #   after_create
    #
    # Returns nothing.
    def ensure_initialized
      user = @nwo ? User.find_by_login(@nwo.split("/")[0]) : nil
      options = {}
      options[:hooks_template] = "#{@template}/hooks" unless @object.nil? || @template.nil? || !GitHub.enterprise?
      options[:files] = { "info/nwo" => @nwo } unless @object.nil? || @nwo.nil?
      options[:initial_branch] = @default_branch if @default_branch
      if FeatureFlag.vexi.enabled?(:reftable_repo_creation, user, default: false)
        options[:ref_format] ||= :reftable
      end
      if @hash_algo
        options[:hash_algo] = @hash_algo
        # Gists do not have an ID until after a 3PC operation has happened and
        # cannot make Spokes API calls until they have an ID.  Set the hash
        # algorithm when creating the object here so that we do not attempt to
        # make a Spokes API call to look it up during the creation process.
        #
        # Other types of repositories do not have this method and thus this does
        # nothing for them.
        @object.hash_algo = GitHub::HashAlgorithm.from_sym(@hash_algo) if @object.respond_to?(:hash_algo=)
      end
      @rpc.ensure_initialized(options)
    end

    # Runs a few common tasks after git repos are created.
    #
    # Returns nothing.
    def after_create
      correct_hooks_symlink

      if !@via_spokes
        write_nwo_file
      end
    end

    # verify that the repo.git/hooks symlink is in place and symlinked
    # to the appropriate hooks directory. This is used primarily in
    # development environments since the RAILS_ROOT is variable.
    def correct_hooks_symlink
      return if @object.nil?
      return if @template.nil?
      return unless GitHub.enterprise?
      link_source = "#{@template}/hooks"
      if File.exist?(link_source)
        @rpc.symlink_hooks_directory(link_source: link_source)
      end
    end

    def write_nwo_file
      return if @object.nil?
      return if @nwo.nil?
      @rpc.fs_write("info/nwo", @nwo)
      # We don't update the DGit checksum here.  RepoCreator's callers do that.
    rescue Object => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
    end

    def same_routes?(object, parent)
      object.dgit_read_routes.map(&:host).sort == parent.dgit_read_routes.map(&:host).sort
    end
  end
end
