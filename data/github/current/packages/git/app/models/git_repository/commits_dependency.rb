# typed: true
# frozen_string_literal: true

# Repository associations and methods related to reading and writing
# git commits. This mostly deals with accessing Commit objects.
#
# The Repository#commits object exposes a bunch of collection methods. See the
# CommitsCollection model for all available collection methods.
module GitRepository
  module CommitsDependency
    extend T::Helpers

    requires_ancestor { Kernel }
    requires_ancestor { ICommitsDependency }
    requires_ancestor { GitHub::FlipperActor }
    requires_ancestor { TreeListable }
    requires_ancestor { GH::Interfaces::DefaultBranch }

    module ICommitsDependency
      extend T::Helpers

      abstract!

      sig { abstract.returns(Promise[NilClass]) }
      def async_network; end

      sig { abstract.params(commitish: T.nilable(String)).returns(T.nilable(String)) }
      def ref_to_sha(commitish); end
    end

    # The main commits association. The collection object includes a number of
    # special methods for reading and writing commits from underlying git
    # storage.
    #
    # Returns a CommitsCollection bound to this repository.
    def commits
      @commits ||= CommitsCollection.new(self)
    end

    # Public: Resolve a string ref name, sha1, or special revision syntax to a
    # Commit object. This first looks up the full object id with ref_to_sha and
    # then loads the commit info.
    #
    # commitish - Anything that can be resolved to a commit: ref name, oid, short
    #             sha, whatever.
    #
    # Returns a Commit object or nil when the commitish can not be resolved.
    def commit_for_ref(commitish)
      if commit_oid = ref_to_sha(commitish)
        commits.find(commit_oid)
      end
    end

    # Public: Find the last commit which touched the given path as of the given
    #   commitish.
    #
    # commitish - Anything that can be resolved to a commit, or nil for default ref
    # path      - The path in question, or root if blank.
    #
    # Returns a Promise<Commit> object
    def async_last_touched(commitish, path)
      async_network.then do
        commitish ||= T.let(default_branch, T.nilable(String))
        commit = commits.last_touched(commitish, path)
        next if commit.nil?

        # reload the object via the platform loader so that the expected features are checked
        # for commit trailers. This step will go away with this entire method once
        # we have caching set up for GitRPC list_revision_history_multiple.
        Platform::Loaders::GitObject.load(self, commit.oid, expected_type: "commit")
      end
    end

    # Public: List commit history starting at the given commit and walking the
    # given number of maximum versions. This gives back oids only, use #history
    # to list Commit objects.
    #
    # commit_oid - The string oid of a commit to start from. This must be a full
    #              oid, not a ref or abbreviated sha1.
    # max        - Maximum number of revisions to include in result list.
    # skip       - Number of commits to skip before listing.
    # path       - Optional path to tree entry to filter history on.
    #
    # Returns an array of commit oid strings.
    def revision_list(commit_oid, max = nil, skip = 0, path = nil, ignore_merge_commits = false)
      return [] if commit_oid.nil?

      options = {}
      options["limit"] = max.to_i if max
      options["offset"] = skip.to_i if skip != 0
      options["path"] = path.sub(/\A\/+/, "") if path
      options["ignore_merge_commits"] = ignore_merge_commits

      rpc.list_revision_history(commit_oid, options)
    end

    # Public: Create a blame report for a file in the repository starting at a
    # certain version.
    #
    # commit_oid   - The commit oid string of where to start.
    # path         - The full path to the file in the repository to blame.
    # line_numbers - An optional array of line numbers to scope the blame to.
    # since        - An optional date to scope blame to.
    # timeout      - An optional timeout to pass to gitrpc
    #
    # Returns a Blame object.
    def blame(commit_oid, path, line_numbers: [], since: nil, timeout: nil, incremental: false, skip_cache: false, qos: nil)
      Blame.new(self, commit_oid, path, line_numbers: line_numbers, since: since, timeout: timeout, incremental: incremental, skip_cache: skip_cache)
    end

    # Deprecated: Finds a slice of WillPaginate'd commits for this repo.
    # Cached to all hell unless you pass in an options Hash.
    #
    # NOTE The commits.paged_history should be used instead where possible. This
    # method should only be used when you need to filter on author, since, or
    # until which are not yet supported by the new APIs.
    #
    # start_sha - The SHA to start at, e.g. "master"
    # page      - The page we're on. Default: 1
    # per_page  - How many commits per page. Default: 30
    # options   - A Hash of options to pass along to `git.log`.
    #
    # Returns a WillPaginate::Collection of commits.
    #
    # TODO Implement history listing command in gitrpc that supports filtering by
    # author, committer, and commit message. Move to commits.paged_history.
    def paged_commits(start_sha, page = 1, per_page = 30, options = {})
      page = 1 if page.blank? || page.to_i < 1
      page = (page || 1).to_i
      options.delete(:path) if options[:path].blank?
      commit_oid = ref_to_sha(start_sha)
      raise GitRPC::ObjectMissing unless commit_oid

      # Returns an empty list if the author/committer passed is Organization instead of returning all commits.
      # This is because organizations cannot author commits.
      # See https://github.com/github/github/issues/49128.
      return [] if options[:author].is_a?(Organization) || options[:committer].is_a?(Organization)

      author_emails = get_user_emails(:author, options)
      committer_emails = get_user_emails(:committer, options)

      if self.feature_enabled?(:remove_enterprise_managed_business_from_options)
        options.delete(:enterprise_managed_business) if options.key?(:enterprise_managed_business)
      end

      path = nil

      collection =
        if author_emails.empty? && committer_emails.empty? && (options.empty? || (options.size == 1 && path = options[:path]))
          commits.paged_history(commit_oid, page, per_page, path)
        else
          skip = (page - 1) * per_page

          options[:n]    ||= per_page + 1
          options[:skip] ||= skip

          if options[:path]
            path = options.delete(:path).sub(%r{\A/+}, "")
          end

          pcl_opts = {}
          pcl_opts[:path] = path
          pcl_opts[:author_emails] = author_emails
          pcl_opts[:committer_emails] = committer_emails
          pcl_opts[:since_time] = options[:since]
          pcl_opts[:until_time] = options[:until]
          pcl_opts[:skip] = options[:skip]
          pcl_opts[:max_count] = options[:n]

          revisions = rpc.paged_commits_log(commit_oid, pcl_opts)
          collection = CommitsCollection::PaginatedCommitCollection.new(page, per_page, skip + revisions.length)
          collection.replace(commits.find(revisions.shift(per_page)).compact)
        end

      filters = {
        path: path,
        starting_oid: commit_oid,
        author_emails: author_emails,
        committer_emails: committer_emails,
        since: options[:since],
        until: options[:until],
      }

      filters.delete_if { |_, v| v.blank? }

      collection.filters = filters
      collection
    end

    # Internal: Return the emails for a user (if there are any).
    #
    # Used in #paged_commits to DRY up author and committer filter searches since
    # we want to do the same email address search for each field.
    #
    # kind    - a Symbol for `:author` or `:committer` so that we can retrieve the correct data from `options`
    # options - A Hash of options that the user is filtering on
    #
    # Returns an Array.
    def get_user_emails(kind, options)
      case options[kind]
      when User
        user = options.delete(kind)
        emails = user.emails.map(&:email)
      when String
        email = options.delete(kind)
        emails = [email]
      else
        options.delete(kind)
        emails = []
      end

      if options[:enterprise_managed_business]
        non_emu_emails = emails.map { |e| options[:enterprise_managed_business].remove_shortcode(e) }
        emails.concat(non_emu_emails)
      end

      emails
    end

    # placeholder exception class for tracking crlf weirdness
    # https://github.com/github/github/pull/12172
    class CRLFError < StandardError
    end

    # Internal: normalize content provided to Ref#create_commit.
    #
    # Designed to sanitize user input from a graphql mutation, this method appends a trailing
    # newline and matches the existing newline format for the file if it exists.
    #
    # content    - the String of the blob's new content
    # parent_oid - the String commit oid of the parent commit
    # path       - the path at which this content will be stored
    #
    # Returns the content with sanitized line endings.
    def normalize_line_endings(content, parent_oid, path)
      content += "\r\n" unless content.ends_with?("\n") # yes, \r\n. The next line will make it \n if applicable

      if blob(parent_oid, path).nil?
        content.gsub("\r\n", "\n")
      else
        preserve_line_endings(parent_oid, path, content)
      end
    end

    # Deprecated: Forms POST \r\n, which will completely mess up your blob if
    # your line endings are just \n.
    #
    # Given a tree, a path to a blob, and new content for that blob,
    # this method will check what the current line endings are in the
    # blob and ensure the new content retains those line endings.
    #
    #    tree - String tree SHA owning the blob
    #    path - String path to the blob
    # content - String with the blob's new content
    #
    # Returns a String
    def preserve_line_endings(tree, path, content)
      Failbot.push("git.commit.tree.oid": tree, "code.filepath": path)

      if tree.blank?
        GitHub.dogstats.increment("repository", tags: ["action:preserve_line_endings", "error:tree_blank"])
        boom = CRLFError.new("blank tree")
        boom.set_backtrace(caller)
        Failbot.report_trace(boom)
        return content
      end

      blob = blob(tree, path, { truncate: false, limit: 2.megabytes })
      if blob.blank?
        GitHub.dogstats.increment("repository", tags: ["action:preserve_line_endings", "error:blob_blank"])
        boom = CRLFError.new("blank blob")
        boom.set_backtrace(caller)
        Failbot.report_trace(boom)
        return content
      end

      tags = ["action:preserve_line_endings"]
      line_endings = if blob.has_mixed_line_endings?
        "mixed"
      elsif blob.has_windows_line_endings?
        "windows"
      elsif blob.has_unix_line_endings?
        "unix"
      else
        "unknown"
      end
      tags << "type:#{line_endings}"
      GitHub.dogstats.increment("repository", tags: tags)

      # If the content has even a single Windows line-ending, we normalize the entire file to that.
      # More explanation in https://github.com/github/github/pull/95026
      if blob.has_windows_line_endings?
        content
      else
        content.gsub(/\r\n/, "\n")
      end
    end
  end
end
