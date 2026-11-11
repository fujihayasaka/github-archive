# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssuePlan < Platform::Loader
      IssuePlanData = T.type_alias { T::Hash[Symbol, T.untyped] }

      class BlobResult < T::Struct
        prop :body, T.nilable(String)
        prop :error_message, T.nilable(String)
      end

      ERROR_FILE_TOO_LARGE = "The plan file exceeds the maximum size. Try reducing its size."
      ERROR_FETCH_FAILED = "There was an error loading the plan. Please try again."

      sig do
        params(
          repository_id: Integer,
          viewer: T.nilable(User),
          issue: ::Issue
        ).returns(Promise[T.nilable(IssuePlanData)])
      end
      def self.load(repository_id, viewer, issue)
        self.for(repository_id, viewer).load(issue)
      end

      sig { params(repository_id: Integer, viewer: T.nilable(User)).void }
      def initialize(repository_id, viewer)
        @repository_id = repository_id
        @viewer = viewer
      end

      sig do
        params(
          issues: T::Array[::Issue]
        ).returns(T::Hash[::Issue, T.nilable(IssuePlanData)])
      end
      def fetch(issues)
        repo = Repository.find_by(id: @repository_id)
        return nil_results(issues) if repo.nil?
        return nil_results(issues) unless issues.first&.plan_feature_enabled?(actor: @viewer, repo: repo)

        default_branch = repo.default_branch
        return nil_results(issues) unless default_branch

        default_branch_oid = repo.default_branch_ref&.target_oid
        return nil_results(issues) unless default_branch_oid

        load_plans(issues, repo: repo, default_branch: default_branch, default_branch_oid: default_branch_oid)
      rescue GitRPC::BadObjectState, GitRPC::InvalidRepository,
             SpokesAPI::Error, SpokesAPI::NotFound
        error_results(issues, ERROR_FETCH_FAILED)
      end

      private

      sig { params(issues: T::Array[::Issue]).returns(T::Hash[::Issue, NilClass]) }
      def nil_results(issues)
        issues.to_h { |issue| [issue, nil] }
      end

      sig do
        params(
          issues: T::Array[::Issue],
          error_message: String,
        ).returns(T::Hash[::Issue, IssuePlanData])
      end
      def error_results(issues, error_message)
        issues.to_h do |issue|
          [issue, {
            body: nil,
            branch: nil,
            file_path: issue.plan_file_path,
            issue: issue,
            error_message: error_message,
          }]
        end
      end

      sig do
        params(
          issues: T::Array[::Issue],
          repo: Repository,
          default_branch: String,
          default_branch_oid: String
        ).returns(T::Hash[::Issue, T.nilable(IssuePlanData)])
      end
      def load_plans(issues, repo:, default_branch:, default_branch_oid:)
        linked_branches = most_recent_linked_branch_per_issue(issues)
        linked_branches = filter_accessible_linked_branches(linked_branches, issue_repo: repo)
        repo_for_issue = resolve_target_repos(issues, linked_branches, repo)
        issues_by_repo = group_issues_by_target_repo(issues, repo_for_issue)

        results = {}
        issues_by_repo.each do |target_repo, repo_issues|
          default_oid = target_repo.id == repo.id ? default_branch_oid : nil
          plan_objects = read_plan_blobs(target_repo, repo_issues, linked_branches, default_oid)

          repo_issues.each_with_index do |issue, index|
            results[issue] = build_plan_data(
              issue: issue,
              blob: plan_objects[index],
              target_repo: target_repo,
              branch_ref: linked_branches[issue.id],
              default_branch: default_branch,
            )
          end
        end

        results
      end

      sig do
        params(
          issues: T::Array[::Issue]
        ).returns(T::Hash[Integer, ::BranchIssueReference])
      end
      def most_recent_linked_branch_per_issue(issues)
        refs = ::BranchIssueReference
          .where(issue_id: issues.map(&:id))
          .includes(:branch_repository)
          .order(id: :desc)

        first_ref_per_issue = {}
        refs.each do |ref|
          first_ref_per_issue[ref.issue_id] ||= ref
        end
        first_ref_per_issue
      end

      sig do
        params(
          linked_branches: T::Hash[Integer, ::BranchIssueReference],
          issue_repo: Repository
        ).returns(T::Hash[Integer, ::BranchIssueReference])
      end
      def filter_accessible_linked_branches(linked_branches, issue_repo:)
        return linked_branches if linked_branches.empty?

        linked_branches.select do |_issue_id, ref|
          next true if ref.branch_repository_id == issue_repo.id

          ref.branch_repository&.resources&.contents&.readable_by?(@viewer) || false
        end
      end

      sig do
        params(
          issues: T::Array[::Issue],
          linked_branches: T::Hash[Integer, ::BranchIssueReference],
          issue_repo: Repository
        ).returns(T::Hash[::Issue, Repository])
      end
      def resolve_target_repos(issues, linked_branches, issue_repo)
        cross_repo_ids = linked_branches.values
          .map(&:branch_repository_id)
          .uniq
          .reject { |id| id == issue_repo.id }
        cross_repos = cross_repo_ids.empty? ? {} : Repository.where(id: cross_repo_ids).index_by(&:id)

        issues.to_h do |issue|
          branch_ref = linked_branches[issue.id]
          target_repo = if branch_ref
            cross_repos[branch_ref.branch_repository_id] || issue_repo
          else
            issue_repo
          end
          [issue, target_repo]
        end
      end

      sig do
        params(
          issues: T::Array[::Issue],
          repo_for_issue: T::Hash[::Issue, Repository]
        ).returns(T::Hash[Repository, T::Array[::Issue]])
      end
      def group_issues_by_target_repo(issues, repo_for_issue)
        grouped = {}
        issues.each do |issue|
          repo = T.must(repo_for_issue[issue])
          grouped[repo] ||= []
          grouped[repo] << issue
        end
        grouped
      end

      sig do
        params(
          target_repo: Repository,
          issues: T::Array[::Issue],
          linked_branches: T::Hash[Integer, ::BranchIssueReference],
          default_branch_oid: T.nilable(String)
        ).returns(T::Array[T.untyped])
      end
      def read_plan_blobs(target_repo, issues, linked_branches, default_branch_oid)
        selectors = issues.map do |issue|
          treeish = treeish_for_issue(linked_branches[issue.id], default_branch_oid)
          build_blob_selector(treeish, issue.plan_file_path)
        end

        selectors
          .each_slice(SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE)
          .flat_map { |batch| target_repo.spokes_api.read_objects_by(batch).objects.to_a }
      end

      sig do
        params(
          branch_ref: T.nilable(::BranchIssueReference),
          default_branch_oid: T.nilable(String)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def treeish_for_issue(branch_ref, default_branch_oid)
        if branch_ref
          name = branch_ref.branch_name
          qualified_name = name.start_with?("refs/") ? name : "refs/heads/#{name}"
          { revision: { name: qualified_name } }
        else
          { oid: { id: T.must(default_branch_oid) } }
        end
      end

      sig do
        params(
          treeish: T::Hash[Symbol, T.untyped],
          file_path: String
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def build_blob_selector(treeish, file_path)
        {
          by_treeish_and_path: {
            treeish: treeish,
            path: { name: file_path }
          },
          object_type: { type: :TYPE_BLOB }
        }
      end

      sig do
        params(
          issue: ::Issue,
          blob: T.untyped,
          target_repo: Repository,
          branch_ref: T.nilable(::BranchIssueReference),
          default_branch: String
        ).returns(IssuePlanData)
      end
      def build_plan_data(issue:, blob:, target_repo:, branch_ref:, default_branch:)
        result = extract_blob_content(target_repo, blob)

        {
          body: result.body,
          branch: branch_ref ? branch_ref.branch_name : default_branch,
          file_path: issue.plan_file_path,
          issue: issue,
          error_message: result.error_message,
        }
      end

      sig { params(repo: Repository, obj: T.untyped).returns(BlobResult) }
      def extract_blob_content(repo, obj)
        return BlobResult.new(body: nil, error_message: nil) if obj.nil?
        return BlobResult.new(body: nil, error_message: ERROR_FILE_TOO_LARGE) if obj.error_object&.error_reason == :ERROR_REASON_TOO_LARGE
        return BlobResult.new(body: nil, error_message: nil) if obj.error_object&.error_reason == :ERROR_REASON_MISSING
        return BlobResult.new(body: nil, error_message: ERROR_FETCH_FAILED) if obj.error_object&.error_reason.present?
        return BlobResult.new(body: nil, error_message: ERROR_FETCH_FAILED) unless obj.object&.type == :TYPE_BLOB
        return BlobResult.new(body: nil, error_message: ERROR_FILE_TOO_LARGE) if obj.object.size > ::Issue::PlanDependency::MAX_PLAN_FILE_SIZE

        data = if obj.truncated
          repo.spokes_api.get_blob_contents_streaming(obj.object.oid.id)
        else
          obj.blob_object&.data
        end

        return BlobResult.new(body: nil, error_message: ERROR_FETCH_FAILED) if data.nil?
        return BlobResult.new(body: nil, error_message: nil) if data.empty?

        BlobResult.new(body: GitHub::Encoding.try_guess_and_transcode(data), error_message: nil)
      end
    end
  end
end
