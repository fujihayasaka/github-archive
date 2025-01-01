# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Commit < Platform::Objects::Base
      description "Represents a Git commit."

      def initialize(*)
        super
        merge_root_commit_arguments!
      end

      implements_node templates: [[:rc, :repo_id, :oid]], as: "C", ready_date: Platform::Helpers::GlobalId::COHORT_4, uses_database_id: false do |commit|
        commit.async_repository.then do |repository|
          {
            prefix: :rc,
            repo_id: repository.id,
            oid: commit.oid
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, commit)
        permission.async_repo_and_org_owner(commit).then do |repo, org|
          permission.access_allowed?(:get_commit, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::GitObject
      implements Interfaces::Subscribable
      implements Interfaces::UniformResourceLocatable

      field :tree, Objects::Tree, description: "Commit's root Tree", null: false

      def tree
        Platform::Loaders::GitObject.load(
          @object.repository,
          @object.tree_oid,
          expected_type: :tree,
          path_prefix: ::Tree::ROOT_PATH, # By definition, a tree loaded from a commit is at root level.
        )
      end

      field :file, Objects::TreeEntry, description: "The tree entry representing the file located at the given path.", null: true do
        argument :path, String, description: "The path for the file", required: true
      end

      def file(path:)
        tree_entry = ::TreeEntry.new(@object.repository, @object.repository.rpc.read_tree_entry(@object.tree_oid, path))
        if tree_entry.size_over_limit?
          raise Errors::Unprocessable, "Could not resolve file over 10mb."
        else
          tree_entry
        end
      rescue GitRPC::NoSuchPath, GitRPC::ObjectMissing
        raise Errors::NotFound, "Could not resolve file for path '#{path}'."
      end

      field :committed_date, Scalars::DateTime, "The datetime when this commit was committed.", null: false

      field :authored_date, Scalars::DateTime, "The datetime when this commit was authored.", null: false

      field :pushed_date, Scalars::DateTime, "The datetime when this commit was pushed.", null: true do
        deprecated(
          start_date: Date.new(2023, 3, 28),
          reason: "`pushedDate` is no longer supported.",
          superseded_by: nil,
          owner: "darthwillis",
        )
      end

      def pushed_date
        nil
      end

      field :message, String, "The Git commit message", null: false

      field :message_headline, String, "The Git commit message headline", method: :short_message_text, null: false
      field :message_body, String, "The Git commit message body", null: false

      def message_body
        @object.message_body_text || ""
      end

      field :repository, Objects::Repository, "The Repository this commit belongs to", null: false

      TREE_PATH_TEMPLATE = Addressable::Template.new("/{user}/{repo}/tree/{oid}")

      url_fields description: "The HTTP URL for this commit" do |commit|
        commit.async_path
      end

      url_fields prefix: "tree", description: "The HTTP URL for the tree of this commit" do |commit|
        commit.repository.async_owner.then do |owner|
          TREE_PATH_TEMPLATE.expand user: owner.display_login, repo: commit.repository.name, oid: commit.oid
        end
      end

      field :author, Objects::GitActor, "Authorship details of the commit.", method: :author_actor, null: true

      field :authors, Connections::GitActor, description: <<~DESCRIPTION, null: false, connection: true do
          The list of authors for this commit based on the git author and the Co-authored-by
          message trailer. The git author will always be first.
        DESCRIPTION

        argument :unique_users, Boolean, description: "Ensure that only the first GitActor is returned when two GitActors have the same user.", visibility: :internal, default_value: false, required: false
      end

      def authors(**arguments)
        if arguments[:unique_users]
          @object.async_unique_visible_author_actors(@context[:viewer]).then do |author_actors|
            ArrayWrapper.new(author_actors)
          end
        else
          ArrayWrapper.new(@object.author_actors)
        end
      end

      field :on_behalf_of, Objects::Organization, description: "The organization this commit was made on behalf of.", null: true

      def on_behalf_of
        @object.async_on_behalf_of
      end

      field :parents, Connections.define(Objects::Commit), description: "The parents of a commit.", null: false, connection: true

      def parents
        Platform::Loaders::GitObject.load_all(@object.repository, @object.parent_oids).then do |commits|
          ArrayWrapper.new(commits)
        end
      end

      field :committer, Objects::GitActor, "Committer details of the commit.", method: :committer_actor, null: true

      field :committed_via_web, Boolean, method: :committed_via_web?, description: "Check if committed via GitHub web UI.", null: false

      field :authored_by_committer, Boolean, method: :async_authored_by_committer?, description: "Check if the committer and the author match.", null: false

      field :diff, Objects::Diff, mobile_only: true, description: "The diff of changes introduced by this commit.", null: true, extras: [:lookahead]

      def diff(lookahead:)
        use_summary = Helpers::Diff.use_summary?(lookahead)
        Helpers::Diff.for(head_repo_id:     @object.repository.id,
                          base_repo_id:     @object.repository.id,
                          start_ref_or_oid: @object.first_parent_oid,
                          end_ref_or_oid:   @object.oid,
                          base_commit_oid:  @object.first_parent_oid,
                          use_summary:      use_summary,
                          compare_repo:     @object.repository)
      end

      field :additions, Integer, description: "The number of additions in this commit.", null: false

      def additions
        diff_summary ? diff_summary.additions : raise(Platform::Errors::ServiceUnavailable.new("The additions count for this commit is unavailable."))
      end

      field :deletions, Integer, description: "The number of deletions in this commit.", null: false

      def deletions
        diff_summary ? diff_summary.deletions : raise(Platform::Errors::ServiceUnavailable.new("The deletions count for this commit is unavailable."))
      end

      field :changed_files,
       Integer,
        description: "We recommend using the `changedFilesIfAvailable` field instead of `changedFiles`, as `changedFiles` will cause your request to return an error if GitHub is unable to calculate the number of changed files.",
        null: false,
        deprecated: {
          start_date: Date.new(2022, 9, 7),
          reason: "`changedFiles` will be removed.",
          superseded_by: "Use `changedFilesIfAvailable` instead.",
          owner: "adamshwert",
        }

      def changed_files
        diff_summary ? diff_summary.changed_files : raise(Platform::Errors::ServiceUnavailable.new("The changedFiles count for this commit is unavailable."))
      end

      field :changed_files_if_available, Integer, description: "The number of changed files in this commit. If GitHub is unable to calculate the number of changed files (for example due to a timeout), this will return `null`. We recommend using this field instead of `changedFiles`.", null: true

      def changed_files_if_available
        diff_summary ? diff_summary.changed_files : nil
      end

      field :message_headline_html, Scalars::HTML, description: "The commit message headline rendered to HTML.", null: false, method: :async_short_message_html

      field :message_body_html, Scalars::HTML, description: "The commit message body rendered to HTML.", null: false, method: :async_message_body_html

      field :short_message_body_html, Scalars::HTML, description: "A truncated version of the message body, rendered as HTML", null: false, visibility: :under_development do
        argument :limit, Integer, "Limit the length of the returned HTML.", default_value: 150,
          required: false
      end

      def short_message_body_html(limit:)
        @object.async_truncated_message_body_html(limit)
      end

      field :history, Connections::CommitHistory, null: false,
        # Turn off GraphQL-Ruby's connection wrapper so that we can
        # return a connection object from the resolver.
        connection: false,
        description: "The linear commit history starting from (and including) this commit, in the same order as `git log`." do
        has_connection_arguments
        argument :path, String, "If non-null, filters history to only show commits touching files under this path.", required: false
        argument :author, Inputs::CommitAuthor, "If non-null, filters history to only show commits with matching authorship.", required: false
        argument :since, Scalars::GitTimestamp, "Allows specifying a beginning time or date for fetching commits. Unexpected results may be returned for dates not between 1970-01-01 and 2099-12-13 (inclusive).", required: false
        argument :until, Scalars::GitTimestamp, "Allows specifying an ending time or date for fetching commits. Unexpected results may be returned for dates not between 1970-01-01 and 2099-12-13 (inclusive).", required: false
      end

      def history(**arguments)
        arguments[:commit_oid] = @object.oid
        connection = ConnectionWrappers::CommitHistory.new(
          @object.repository,
          first: arguments[:first],
          last: arguments[:last],
          before: arguments[:before],
          after: arguments[:after],
          arguments: arguments,
          parent: @object
        )

        connection
      end

      field :comments, resolver: Resolvers::CommitComments, description: "Comments made on the commit.", connection: true

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false

      def websocket
        GitHub::WebSocket::Channels.commit(@object.repository, @object.oid)
      end

      field :updates_channel, String, "Channel value for subscribing to live updates.", null: true, mobile_only: true, required_capabilities: [:subscribe_alive_events]

      def updates_channel
        GitHub::WebSocket::Channels.signed_commit(@object.repository, @object.oid)
      end

      field :has_signature, Boolean, visibility: :internal, description: "The commit has a signature", method: :has_signature?, null: false

      field :signature, Interfaces::GitSignature, description: "Commit signing information, if present.", method: :async_signature, null: true

      field :verification_status, Enums::CommitVerificationStatus,
        visibility: :internal,
        null: true,
        description: "Status of a commit when at the least one author has enabled vigilant mode",
        method: :async_verification_status

      field :status, Objects::Status, description: "Status information for this commit", null: true

      def status
        Objects::Status.load_from_repo_and_oid(@object.repository, @object.oid)
      end

      field :has_status_check_rollup, Boolean, visibility: :internal, description: "Does this commit have any Check and Status rollup", null: false

      def has_status_check_rollup
        Platform::Loaders::HasStatusCheckRollup.load(@object.repository, @object.oid)
      end

      field :status_check_rollup, Objects::StatusCheckRollup, description: "Check and Status rollup information for this commit.", null: true, extras: [:lookahead]

      def status_check_rollup(lookahead:)
        overview_only = !lookahead.selects?(:contexts)
        Objects::StatusCheckRollup.load_from_repo_and_oid(@object.repository, @object.oid, overview_only)
      end

      field :blame, Objects::Blame, description: "Fetches `git blame` information.", null: false do
        argument :path, String, "The file whose Git blame information you want.", required: true
        argument :line_numbers, [Integer], "Filter blame by line numbers", visibility: :internal, required: false
      end

      def blame(**arguments)
        if arguments[:line_numbers]
          invalid_line_numbers = arguments[:line_numbers].select { |n| n <= 0 }

          if invalid_line_numbers.any?
            raise Errors::ArgumentError.new("Invalid line numbers: #{invalid_line_numbers}")
          else
            @object.repository.blame(@object.oid, arguments[:path], line_numbers: arguments[:line_numbers])
          end
        else
          @object.repository.blame(@object.oid, arguments[:path])
        end
      end

      field :tarball_url, Scalars::URI, description: "Returns a URL to download a tarball archive for a repository.\nNote: For private repositories, these links are temporary and expire after five minutes.", null: false

      def tarball_url
        repository = @object.repository

        ac = repository.archive_command(@object.oid, "legacy.tar.gz")
        ac.codeload_url(@context[:viewer])
      end

      field :zipball_url, Scalars::URI, description: "Returns a URL to download a zipball archive for a repository.\nNote: For private repositories, these links are temporary and expire after five minutes.", null: false

      def zipball_url
        repository = @object.repository

        ac = repository.archive_command(@object.oid, "legacy.zip")
        ac.codeload_url(@context[:viewer])
      end

      field :check_suites, Connections.define(Objects::CheckSuite), description: "The check suites associated with a commit.", null: true, connection: true, numeric_pagination_enabled: true do
        argument :filter_by, Inputs::CheckSuiteFilter, "Filters the check suites by this type.", required: false
      end

      def check_suites(**arguments)
        @object.async_repository.then do |repository|
          check_suites = ::CheckSuite.where(head_sha: @object.sha, repository_id: repository.id)

          arguments[:filter_by] ||= {}

          if id = arguments[:filter_by][:app_id].presence
            check_suites = check_suites.for_app_id(id)
          end

          if name = arguments[:filter_by][:check_name].presence
            check_suites = check_suites.with_check_run_named(name, repository.id)
          end

          check_suites
        end
      end

      field :deployments, Connections.define(Objects::Deployment), description: "The deployments associated with a commit.", null: true, connection: true, resolver: Resolvers::CommitDeployments

      field :associated_pull_requests, Connections.define(Objects::PullRequest), description: "The merged Pull Request that introduced the commit to the repository. If the commit is not present in the default branch, additionally returns open Pull Requests associated with the commit", null: true, connection: true do

        argument :order_by, Inputs::PullRequestOrder, "Ordering options for pull requests.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end

      def associated_pull_requests(order_by:)
        @object.async_associated_pull_requests(order_by: order_by,
                                               viewer: @context[:viewer]).then do |pull_requests|
          ArrayWrapper.new(pull_requests)
        end
      end

      field :submodules, Connections.define(Objects::Submodule), description: "Returns a list of all submodules in this repository as of this Commit parsed from the .gitmodules file.", null: false, connection: true

      def submodules
        @object.async_repository.then do |repo|
          repo.async_submodules(@object.oid).then do |submods|
            ArrayWrapper.new(submods.values)
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        Interfaces::GitObject.load_from_next_global_id(parsed_id)
      end

      def self.load_from_global_id(id)
        Interfaces::GitObject.load_from_global_id(id)
      end

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          begin
            repository && repository.commit_for_ref(params[:name])
          rescue GitRPC::ObjectMissing
            nil
          end
        end
      end

      private

      # Make a diff summary without fully loading the corresponding `GitHub::Diff` object.
      # This requires less GitRPC work and it can satisfy some of the summary fields.
      # In case the whole `GitHub::Diff` is loaded, this GitRPC call will be cached anyways.
      #
      # @return [GitRPC::Diff::Summary]
      def diff_summary
        if defined?(@diff_summary)
          @diff_summary
        else
          diff = GitHub::Diff.new(
            @object.repository,
            @object.first_parent_oid,
            @object.oid,
          )
          summary = diff.summary
          @diff_summary = if summary.available?
            summary
          else
            nil
          end
        end
      end

      # Merge commit arguments that will be used later in TreeEntry objects.
      # We only merge the commit arguments if they have not been merged by a
      # parent object
      # eg.the Repository#object filed merges root_commit_arguments
      def merge_root_commit_arguments!
        return if context.scoped_context[:root_commit_arguments]
        context.scoped_merge!(root_commit_arguments: { oid: @object.oid })
      end
    end
  end
end
