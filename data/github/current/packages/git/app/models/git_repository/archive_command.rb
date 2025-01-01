# typed: true
# frozen_string_literal: true

module GitRepository
  # This class is responsible for mapping its given input triplet:
  #
  #   { repo object, commitish, archive type }
  #
  # to a hash of info necessary to route to, generate, and serve
  # back an archive to a user.  Codeload has no access to the DB,
  # so it relies on the site/archive API to compute what are the
  # routes, shard path, commit OID, and public-facing filename
  # and MIME type for the archive at hand.
  class ArchiveCommand
    # Error thrown when a given short name is ambiguous
    class RefnameConflictError < StandardError
      attr_reader :variants

      def initialize(variants)
        @variants = variants
      end
    end

    # How long the SignedAuthToken for an archive command lasts.
    TOKEN_EXPIRATION = 5.minutes

    include UrlHelper

    def self.token_scope(git_repo)
      return unless git_repo
      "#{git_repo.class.name}:Archive:#{git_repo.token_scope}"
    end

    # Retrieve the qualified name for the default branch if +rev+ is blank,
    # the qualified name for +rev+ if we can find it, or +rev+ if it
    # cannot be found.
    #
    # If +rev+ is a short name and it's ambiguous, a RefnameConflictError is raised
    def self.qualified_name_from_revision(repo, rev)
      ref = if rev.blank?
        repo.default_branch_ref
      else
        ArchiveCommand.find_a_single_ref(repo, rev)
      end

      ref&.qualified_name
    end

    # Returns the ref given by +rev+ if it's a full refname. If it's a short name,
    # returns the branch or tag with that short-name. If there are multiple refs
    # with that short-name it raises a RefnameConflictError
    def self.find_a_single_ref(repo, rev)
      return repo.refs.find(rev) if rev.starts_with?("refs/")

      variants = repo.refs.select { |r| r.name == rev }
      raise RefnameConflictError.new(variants) if variants.length > 1

      variants[0]
    end

    # git_repo  - A git repo object (e.g. Repository, Gist etc). Must respond to
    #             the following methods:
    #             - id
    #             - private?
    #             - name_with_owner_for_archive
    #             - to_s
    #             - rpc
    #             - commits
    #             - dgit_read_routes (a list of routes that respond to "host" and "path")
    #             - shard_path
    #             - route
    # commitish - A String ref that maps to a Git Commit: a SHA, a branch name,
    #             or a tag name.
    # type      - The String or Symbol type of archive to build: 'tar.gz' or 'zip'
    def initialize(git_repo, commitish, type, actor_id: nil, actor_token: nil)
      raise ArgumentError unless type =~ /(legacy\.)?(zip|tar\.gz|blob)$/

      @type       = type
      @git_repo   = git_repo
      @commitish  = commitish.to_s
      @commit_oid = nil
      @actor_id     = actor_id
      @actor_token  = actor_token
    end

    def codeload_type
      @type
    end

    def codeload_url(user)
      url = "#{GitHub.urls.codeload_url}/#{@git_repo.name_with_owner_for_archive}/#{codeload_type}/#{escape_url_branch(@commitish)}"
      if user && (@git_repo.private? || GitHub.private_mode_enabled? || user.spammy?)
        options = {}.tap do |opts|
          opts[:scope]   = ArchiveCommand.token_scope(@git_repo)
          opts[:expires] = TOKEN_EXPIRATION.from_now

          if user.is_a?(Bot) && user.installation.present?
            opts[:data] = { installation_id: user.installation.id }
          end
        end

        token = user.signed_auth_token(options)

        url += "?token=#{token}"
      end
      url
    end

    # Public: Builds a Hash ready to be serialized to JSON.  The values of the
    # hash are default values that Codeload can use to construct a `git
    # archive` command.
    #
    # Returns a Hash.
    def to_hash
      return if !archivable?
      result = {
        # codeload
        type: @type,
        file: filename,
        mime_type: @type == "zip" ? "application/zip" : "application/x-gzip",
        prefix: prefix,
        commit: commit_oid,
        treeish: treeish_oid,
        nwo: @git_repo.name_with_display_owner,
        actor_id: @actor_id,
        actor_token: @actor_token,
        # for redis stats
        commitish: @commitish,
        repo: @git_repo.id,
      }
      # dgit-compatible routes
      result[:routes] = @git_repo.dgit_read_routes.map { |route| { route: route.resolved_host, path: route.path } }
      result[:use_librarian] = @git_repo.lfs_in_archives_enabled?
      # old-style routes
      result.update \
        path: @git_repo.shard_path,
        route: @git_repo.route
      result
    end

    # Public: Determines if the given commitish is archivable for this
    # Repository.
    #
    # Returns true if a Commit was found, or false.
    def archivable?
      !!commit_oid && !!treeish_oid
    end

    # Public: Gets the fully dereferenced tree oid resolved from the treeish.
    #
    # Returns a String Tree oid.
    def treeish_oid
      return @treeish_oid if @treeish_oid

      query = "#{commit_oid}^{tree}"

      @treeish_oid = begin
                      @git_repo.rev_parse(query)
                    rescue GitRPC::BadRepositoryState, GitRPC::Failure, GitHub::DGit::NotFoundError, SpokesAPI::NotFound, SpokesAPI::InvalidArgument
                      # just 404 if the revision string is bad (Rugged::InvalidError, Rugged::OSError)
                      nil
                    end

      return unless @treeish_oid
      @treeish_oid
    end

    # Public: Gets the fully dereferenced Commit oid resolved from the commitish.
    #
    # Returns a String Commit oid.
    def commit_oid
      return @commit_oid if @commit_oid

      query = if @commitish =~ /\{.*\}\z/
        @commitish
      else
        "#{@commitish}^{}"
      end

      @commit_oid = begin
                      @git_repo.rev_parse(query)
                    rescue GitRPC::BadRepositoryState, GitRPC::Failure, GitHub::DGit::NotFoundError, SpokesAPI::NotFound, SpokesAPI::InvalidArgument
                      # just 404 if the revision string is bad (Rugged::InvalidError, Rugged::OSError)
                      nil
                    end

      return unless @commit_oid

      # temporarily commented out
      # want to check performance on reachability checks
      # @commit_oid = nil unless @git_repo.commits.exist?(@commit_oid, check_reachability: true)

      @commit_oid
    end

    # Public: Gets the filename of the archive that is sent to the user.  Uses
    # #recent_tag_name or #fallback_tag_name.
    #
    # Returns a String filename.
    def filename
      @filename ||= "%s-%s.%s" % [@git_repo, dist_tag, @type]
    end

    BRANCH_PREFIX = "refs/heads/".freeze
    TAG_PREFIX    = "refs/tags/".freeze

    def dist_tag
      @dist_tag ||= begin
        name = @commitish
        if name.start_with?(BRANCH_PREFIX)
          name = name.delete_prefix(BRANCH_PREFIX)
        else
          name = name.delete_prefix(TAG_PREFIX)
        end

        t = (name =~ /^v\d/i) ? name[1..-1] : name
        t = t.gsub /[^a-z0-9\-\_\.]/i, "-"
        t = t.gsub /-{2,}/, "-"
        t
      end
    end

    # Public: String specifying the path prefix of the archive.
    #
    # Returns a String.
    def prefix
      @prefix ||= "#{@git_repo}-#{dist_tag}"
    end
  end
end
