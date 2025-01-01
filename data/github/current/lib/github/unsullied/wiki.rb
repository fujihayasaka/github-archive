# typed: true
# frozen_string_literal: true

# Notes:
# * "home" (case-insensitive) is the default page. If it's not found,
#   a list of pages for the wiki is shown instead.
# * Pages are found based on name without extension.
# * Pages are created with a name and type which is mapped to an extension.
#   The content is run through an html pipeline.
# * Files in subdirs are flattened into the list of pages shown on the right of a wiki
# * Sidebar and Footer are files named "_Sidebar.<ext>" and "_Footer.<ext>"
# * Upon creation, a page name will have any "/" characters replaced with "-" as
#   subdirectories don't appear to be supported by the UI
#
#
# TODO: Make a more efficient "find page in tree" GitRPC call. For you know, the speeds.
#
# wtfs:
# * Submodules?
module GitHub
  module Unsullied
    # Main object representing a wiki
    #
    # Wiki's are made up of markup files backed by a git repository.
    class Wiki
      include GitHub::FlipperActor
      include GitHub::VexiActor

      class Error < StandardError; end
      class DuplicatePageError < Error; end
      class UnwantedEditError < Error; end
      class TitleTooLongError < Error; end

      include ::Repository::RefsDependency
      include ::GitRepository::UrlMethods
      include ::GitRepository::SpokesAdapter
      include ::Repository::Backup
      include ::Repository::LegalHold
      include ::SpokesAPI::ContextDependency

      DEFAULT_REF = "refs/heads/master"
      WIKI_RPC_CACHE_VERSION = 1

      # Public: The Repository object which is the "owner" of this wiki
      attr_reader :repository

      # Public: The GitRPC object used for all git operations performed on this
      # wiki
      def rpc
        @rpc ||= repository.wiki_rpc!
      end

      # Public: A Spokes API client for this wiki.
      def spokes_api(timeout: nil)
        if timeout
          return SpokesAPI::Client.for_wiki(
            repository.id,
            network_id: repository.network_id,
            timeout: timeout,
            context: self.spokes_api_context
          )
        end
        @spokes_api ||=
          SpokesAPI::Client.for_wiki(
            repository.id,
            network_id: repository.network_id,
            context: self.spokes_api_context
          )
      end

      # This is typically only used in tests when a wiki has been
      # overwritten enough that its routes will need to be reloaded.
      def reset_git_cache
        @rpc = nil
      end

      # Perform all RPC operations as if this repo lived in a different
      # network.  This is useful for repos that are being extracted or moved.
      # It only has an effect on DGit repos -- the same effect can be
      # accomplished for non-DGit repos by overriding the network_id.
      def set_rpc_network_override(network)
        @rpc = ::GitRPC.new(
          "dgit:/",
          { delegate: GitHub::DGit::Delegate::Network.new(network.id, original_shard_path),
            info: { real_ip: GitHub.context[:actor_ip], request_id: GitHub.context[:request_id] },
          },
        )
      end

      def original_shard_path
        repository.original_shard_path.sub(/(?<!\.wiki)\.git$/, ".wiki.git")
      end

      def repository_spec
        network_id = network&.id || repository&.network_id
        "#{network_id}/#{id}.wiki"
      end

      # Verify that the repo.wiki.git/hooks symlink is in place and symlinked
      # to the appropriate hooks directory. This is used primarily in
      # development environments since the RAILS_ROOT is variable.
      def correct_hooks_symlink
        return if %w[development test].include?(Rails.env) && repository.name == "github"
        return unless GitHub.enterprise?

        rpc.symlink_hooks_directory
      end

      # Public: The directory prefix to add to all git operations that accept a
      # pathspec. It defaults to "" (root directory).
      attr_reader :directory_prefix

      def initialize(repo, dir_prefix = "")
        @repository = repo
        @directory_prefix = dir_prefix
        @update_callbacks = []
        @latest_page_revisions = {}
      end

      def dgit_repo_type
        GitHub::DGit::RepoType::WIKI
      end

      def namespace
        "wiki"
      end

      def coalesce_dgit_updates?
        false
      end

      def public?
        repository.public?
      end

      # Since this object is passed in a few places that expect a Repository,
      # we need to respond to certain methods in order for things to work
      # correctly.
      delegate :dgit_reload_routes!, :host, :route, :private?, :pushable_by?, to: :repository
      delegate :network, to: :repository
      delegate :id, to: :repository

      def initialize_replicas_from_network
        GitHub::DGit::Maintenance.insert_placeholder_replicas_and_checksums(
          GitHub::DGit::RepoType::WIKI, repository.id, repository.network.id)
        repository.reload
        repository.dgit_reload_routes!
      end

      # Public: For compatibility with Repository since we share the refs usage
      #
      # Always returns false
      def supports_protected_branches?
        false
      end

      # Public: Create both DGit routing (in SQL) and on-disk state for
      # the wiki git repository.  Use this for creating new wikis.
      #
      # Compare to `create_git_repository_on_disk`, below.
      #
      # Returns nothing
      def setup_git_repository(fork_parent_wiki: false)
        initialize_replicas_from_network
        create_git_repository_on_disk(fork_parent_wiki: fork_parent_wiki)
      rescue GitRPC::Error, GitHub::DGit::Error => e
        # remove the records from repository_replicates and repository_checksums
        # if there is a problem creating the repo on disk. This is not as foolproof
        # as a transaction, but should cover most cases until we can bring all
        # transactions into spokes.
        GitHub::DGit::Maintenance.delete_wiki_replicas_and_checksums(repository.network.id, repository.id)
        raise
      end

      # Public: Create the wiki git repository on disk, but not DGit
      # routing in SQL.  Use this in cases where the DGit routes already
      # exist for this wiki, such as moving the wiki from one network to
      # another.
      #
      # Compare to `setup_git_repository`, above.
      #
      # Returns nothing
      def create_git_repository_on_disk(fork_parent_wiki: false)
        creator =
          GitHub::RepoCreator.new(self,
            public: repository.public?,
            template: GitHub.repository_template,
            nwo: "#{repository.name_with_owner}.wiki")

        parent_wiki = repository.parent && repository.parent.unsullied_wiki
        if fork_parent_wiki && parent_wiki && parent_wiki.forkable?
          creator.fork(parent_wiki)
        else
          creator.init
        end

        GitHub::DGit::Maintenance.recompute_checksums(repository, :vote, is_wiki: true, force_dgit_init: true)

      end

      # Public: Is the wiki in a forkable state? Is there data and is it available?
      #
      # Returns boolean
      def forkable?
        exist? && revisions(0, 1).present? && repository.has_wiki?
      end

      # Public: The full name of this wiki; e.g., "owner/repo.wiki"
      #
      # Returns the full name as a String
      def full_name
        repository.full_name + ".wiki"
      end

      # Public: The absolute path on the fileserver for this wiki repository
      #
      # Returns the full path as a String
      def shard_path
        repository.shard_path.sub(/(?<!\.wiki)\.git$/, ".wiki.git")
      end

      # Public: The nwo-style path for this wiki excluding the ".git" suffix
      #
      # Returns a String like "brianmario/mysql2.wiki"
      def short_git_path
        path.chomp(".git")
      end

      # Public: The nwo-style path for this wiki
      #
      # Returns a String like "brianmario/mysql2.wiki.git"
      def path
        repository.wiki_path
      end

      # Public: If the repository is in dgit, the full list of available read replicas
      #
      # Returns an array of objects that respond to host and path.
      def dgit_read_routes
        repository.dgit_wiki_read_routes
      end

      def dgit_delegate_for_update_refs_coordinator
        dgit_delegate
      end

      def dgit_delegate
        GitHub::DGit::Delegate::Wiki.new(network.id, id, original_shard_path, spokes_api_context)
      end

      def recompute_checksums(voting_strategy, read_host, ignore_dissent: false)
        tpc = GitHub::DGit.update_refs_coordinator(self)
        tpc.recompute_checksums(voting_strategy, read_host, ignore_dissent: ignore_dissent)
      end

      # Public: The base URL for this wiki
      #
      # Returns a String like "/brianmario/mysql2/wiki"
      def base_path
        "/#{repository.name_with_display_owner}/wiki"
      end

      # Public: The owner id of this wiki
      #
      # Returns a User id
      def owner_id
        repository.owner_id
      end

      # Public: Forcily disable Git LFS support for wikis.
      # Not sure if this will always be the case, but we need this here for now
      # because Unsullied::Wiki objects are passed around to some places that
      # think they're being handed a Repository object. So we need to adhere
      # to certain APIs.
      #
      # Returns false
      def git_lfs_enabled?
        false
      end

      # Public: Pass a block which will be called after a page creation, update,
      # revert or delete. Anything that changes the repository.
      # This is currently used to make sure we immediately roll the GitRPC
      # cache key for the wiki after a change.
      #
      # Returns nothing
      def on_update(&blk)
        @update_callbacks << blk
      end

      # Public: The default ref for this wiki.
      # This is currently hard-coded.
      #
      # Returns "refs/heads/master"
      def default_ref
        DEFAULT_REF
      end

      # Public: The oid of the most recent commit `ref` points to
      #
      # Returns a 40 character oid String of the oid to which `default_ref` points
      def default_oid
        refs.find(default_ref).try(:target_oid)
      rescue GitHub::DGit::UnroutedError, ::GitRPC::InvalidRepository
      end

      # Public: Check if the wiki repository exists on disk on the fileserver
      #
      # Returns true or false
      def exist?
        # GitRPC client object won't instantiate unless there's at least one dgit route
        GitHub::DGit::Routing.all_repo_replicas(repository.id, true).size > 0 && rpc.exist?
      end

      # Public: The list of revisions for this wiki
      #
      # offset - the offset of which to start listing revisions
      # limit  - the number of revisions to return
      #
      # Returns an array of Commit objects
      def revisions(offset = 0, limit = 30)
        return [] if default_oid.blank?

        opts = {
          "offset" => offset,
          "limit"  => limit,
        }
        opts["path"] = directory_prefix unless directory_prefix.empty?
        oids = rpc.list_revision_history(default_oid, opts)

        commits.find(oids)
      end

      # Public: Fetch the most recent revisions for every file in this repo
      # This uses `blame-tree` to recursively fetch the latest commit oid
      # that touched a file.
      #
      # oid - the oid for the commit of a point in history in the wiki to start
      #       looking up the last commits that touched files
      #
      # Returns a Hash where the key is the full path to the changed file
      # and the value is the commit oid as a 40 character String
      def latest_revisions(oid = default_oid)
        if @latest_page_revisions.key?(oid)
          @latest_page_revisions[oid]
        else
          @latest_page_revisions.clear
          @latest_page_revisions[oid] = self.blame_tree(oid)
        end
      end

      # Public: The number of commits in this wiki as of `oid`
      #
      # oid - the oid for the commit of a point in history in the wiki to start
      #       counting revisions
      #
      # Returns the number of commits since `oid` as an Integer
      def revision_count(oid = default_oid)
        return 0 if oid.blank?

        rpc.count_revision_history(oid, use_bitmap_index: true)
      rescue GitRPC::CommandFailed
        nil
      end

      # Public: Revert the changes that happened between `commit_oid1` and
      # `commit_oid2`.
      #
      # commit_oid1 - a 40 character oid as a String
      # commit_oid2 - a 40 character oid as a String
      # user        - a User object used as the committer information for the
      #               revert commit
      #
      # Returns the oid of the newly created commit as a 40 character String
      def revert(commit_oid1, commit_oid2, user)
        message = "Revert #{commit_oid1}...#{commit_oid2}"

        opts = {
          "message" => message,
          "committer" => {
            "name"  => user.git_author_name,
            "email" => user.git_author_email,
            "time"  => Time.zone.now.iso8601,
          },
        }

        # TODO: Current oid should be a argument passed to revert
        oid = rpc.revert_range(commit_oid1, commit_oid2, opts)
        update_default_ref(oid, user: user)
        oid
      end

      # Public: Generate a diff between two revisions in a wiki
      #
      # commit_oid1 - an oid as a 40 character String. Specify nil to use
      #               commit_oid2's parent commit.
      # commit_oid2 - an oid as a 40 character String.
      #
      # Returns a GitHub::Diff object or nil if the diff operation failed
      def diff(commit_oid1, commit_oid2)
        commit_oid1 = self.spokes_api.resolve_object(object_name: commit_oid1) if commit_oid1
        commit_oid2 = self.spokes_api.resolve_object(object_name: commit_oid2) if commit_oid2

        if commit_oid1.nil?
          commit_data = self.read_objects(
            [commit_oid2],
            :commit
          )
          commit_oid1 = commit_data.first["parents"].first
        end

        ::GitHub::Diff.new(self, commit_oid1, commit_oid2, {})
      rescue ::GitRPC::BadRepositoryState
      end

      # Public: The collection of pages in this wiki.
      # A wiki "page" is a renderable file anywhere in the wiki repo. Even under
      # subdirectories.
      #
      # Returns a GitHub::Unsullied::PagesCollection object
      def pages
        @pages ||= GitHub::Unsullied::PagesCollection.new(self)
      end

      # Public: The collection of files in this wiki.
      # This represents all files in the wiki, not just "pages"
      #
      # Returns a GitHub::Unsullied::FilesCollection object
      def files
        @files ||= GitHub::Unsullied::FilesCollection.new(self)
      end

      def update_default_ref(oid, user:, reflog: {})
        refs.find_or_build(default_ref).update(oid, user, post_receive: false, backup: false, clear_ref_cache: false, reflog_data: reflog)
        fire_changed_callbacks(oid, user)
      end

      def refs
        return @refs if defined?(@refs)
        @refs = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(self, "default"))
      end

      # No-op. Custom hooks aren't supported for wiki.
      def check_custom_hooks(old_oid, new_oid, qualified_name, options = {})
      end

      # Internal: Called right after any changes are recorded in the wiki's
      # repository.
      #
      # Returns nothing
      def fire_changed_callbacks(new_head_oid, user)
        commit = commits.find(new_head_oid)

        ref_update = Git::Ref::Update.new(repository: self, refname: default_ref,
                                          before_oid: commit.parent_oids.first || GitHub::NULL_OID,
                                          after_oid: new_head_oid)

        if self.feature_enabled?(:push_event_pusher_id)
          RepositoryPushJobTrigger.new(self, user.to_s, [ref_update], Time.current, pusher_id: user&.id).enqueue
        else
          RepositoryPushJobTrigger.new(self, user.to_s, [ref_update], Time.current).enqueue
        end

        @update_callbacks.each do |callback|
          callback.call(new_head_oid)
        end
      end

      # Internal: Hash used by the WikiReceive job
      #
      # after - the oid as a 40 character String of the current revision being
      #         processed by the background job
      #
      # Returns a Hash
      def payload_for_wikireceive(after)
        {
          repo: repository.to_s,
          user: repository.owner.to_s,
          ref: "refs/heads/master",
          after: after,
        }
      end

      # Public: The cache key for this wiki
      #
      # Returns a String
      def cache_key
        ["wiki", hashed_nwo, default_oid].join(":")
      end

      def spokes_cache_key
        "wc:v#{WIKI_RPC_CACHE_VERSION}:#{id}"
      end

      # Internal: The nwo of the owning repository as a SHA256 hash
      #
      # Returns a String
      def hashed_nwo
        ::Digest::SHA256.hexdigest(repository.nwo)
      end

      # Internal: An interator for the git objects in the wiki repository
      #
      # Returns a RepositoryObjectsCollection object
      def objects
        @objects ||= ::RepositoryObjectsCollection.new(self)
      end

      # Internal: An iterator for the commit objects in the wiki repository
      #
      # Returns a CommitsCollection object
      def commits
        @commits ||= ::CommitsCollection.new(self)
      end

      # Internal: Optimize pack files in the wiki repository. This
      # rebuilds all packs that have accumulated since the last maintenance into
      # a single optimized pack and builds bitmap indexes. No objects are pruned
      # during the repack so this method can be used to safely optimize pack
      # storage without any risk of repository corruption.
      #
      # Returns nothing.
      def repack
        GitRPC::Util.with_repack_error_handler do
          rpc.nw_repack
        end
        nil
      end

      # Internal: Noop submodule calls to Wikis as we do not support them
      #
      # Returns nil
      def submodule(*args)
        nil
      end
    end
  end
end
