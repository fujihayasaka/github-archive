# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  # The PullRequest adapter is used to transform a pull request ActiveRecord
  # object into a Hash document that can be indexed in ElasticSearch.
  #
  class PullRequest < ::Elastomer::Adapter
    include Scientist

    DEFAULT_MAX_DOCUMENT_SIZE = T.let(15.megabytes, Integer)

    class MissingCommitInfo < StandardError; end

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    sig { returns(String) }
    def self.index_name
      "PullRequests"
    end

    sig { returns(Symbol) }
    def self.mysql_cluster
      ::PullRequest.cluster_name
    end

    sig { returns(Integer) }
    attr_accessor :bytesize_estimate

    sig { returns(Integer) }
    attr_accessor :max_document_size

    sig { returns(T::Boolean) }
    attr_accessor :skip_commit_info_on_failure

    def initialize(*)
      super
      @bytesize_estimate = 0
      @max_document_size = T.let(options.fetch(:max_document_size, DEFAULT_MAX_DOCUMENT_SIZE), Integer)
      @skip_commit_info_on_failure = T.let(options.fetch(:skip_commit_info_on_failure, false), T::Boolean)
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    sig { returns(T.nilable(::PullRequest)) }
    def model
      if GitHub.flipper[:dont_preload_review_comments].enabled?
        @model ||= ::PullRequest.includes(
          :repository, :user, :base_repository,
          :head_repository, :base_user, :head_user,
          { issue: [:repository, :labels] }
        ).find_by(id: document_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      else
        @model ||= ::PullRequest.includes(
          :repository, :user, :review_comments, :base_repository,
          :head_repository, :base_user, :head_user,
          { issue: [:repository, { comments: :user }, :labels] }
        ).find_by(id: document_id)
      end
    end
    alias :pr :model

    # Document routing information used to co-locate all pull requests for a
    # given repository on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    sig { returns(Integer) }
    def document_routing
      @document_routing ||= (pr&.repository_id)
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    sig { returns(T.nilable(Hash)) }
    def to_hash
      unless pr = model
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash

      @hash = nil

      return unless pr.is_searchable?
      return unless issue = pr.issue
      return unless repository = pr.repository

      # Load the commit information first as we'll throw an error due to any Git related outages. Prevent unusued
      # DB interactions when the git failure will prevent indexing.
      @hash = commit_info

      @hash.merge!(
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        title: pr.title,
        body: ::Search.clean_and_sanitize(pr.body),
        issue_id: issue.id,
        author_id: pr.user_id,
        repo_id: pr.repository_id,
        network_id: repository.network_id,
        public: repository.public?,
        archived: repository.archived?,
        state: issue.state,
        number: pr.number,
        labels: issue.labels.map(&:name),
        head_ref: pr.head_ref_name.downcase,
        base_ref: pr.base_ref_name.downcase,
        created_at: pr.created_at,
        updated_at: pr.updated_at,
        closed_at: pr.closed_at,
        locked_at: pr.locked_at,
        locked: pr.locked?,
        assignee_id: issue.assignees.map(&:id),
        project_ids: issue.projects.pluck(:id),
        memex_project_ids: pr.memex_projects.active_projects.pluck(:id),
        merged: pr.merged?,
        merged_at: pr.merged_at,
        mergeability: git_dependency(default: :unknown) { pr.merge_state.status },
        merge_commit: pr.merged? ? pr.merge_commit_sha : nil,
        status: pr.combined_status.state,
        draft: pr.draft?,
        reviewable_state: pr.reviewable_state,
        review_status: git_dependency(default: []) { pr.review_merge_states },
        mentioned_user_ids: issue.referenced_user_ids,
        mentioned_team_ids: issue.referenced_team_ids,
        participating_user_ids: git_dependency(default: []) { issue.participants.map(&:id) },
        has_closing_reference: pr.close_issue_references.exists?,
        reactions: ActiveRecord::Base.connected_to(role: :reading) { issue.reactions_count },
        requested_reviewer_ids: T.unsafe(pr.review_requests.ready).pending.users.map(&:id),
        requested_reviewer_team_ids: T.unsafe(pr.review_requests.ready).pending.teams.map(&:id),
        reviewer_team_ids: T.unsafe(pr.review_requests).teams.map(&:id),
        reviewer_ids: pr.reviews.map(&:user_id),
        queued: !!pr.in_merge_queue?,
      )

      @hash[:labels].map!(&:downcase)

      @hash.delete :labels if @hash[:labels].blank?
      @hash.delete :mentioned_user_ids if @hash[:mentioned_user_ids].blank?
      @hash.delete :mentioned_team_ids if @hash[:mentioned_team_ids].blank?
      @hash.delete :participating_user_ids if @hash[:participating_user_ids].blank?
      @hash.delete :project_ids if @hash[:project_ids].blank?
      @hash.delete :memex_project_ids if @hash[:memex_project_ids].blank?

      if language = repository.primary_language
        @hash[:language]    = language.linguist_name
        @hash[:language_id] = language.linguist_id
      end

      if milestone = issue.milestone
        @hash[:milestone_num]   = milestone.number
        @hash[:milestone_title] = milestone.title.downcase
        priority_for_milestone = issue.issue_priorities.by_milestone(issue.milestone_id).first
        if priority_for_milestone.present?
          # Convert the priority to a zero-padded string for consistent sorting
          @hash[:milestone_prio] = priority_for_milestone.priority
        end
      end

      @hash[:num_reactions] = ActiveRecord::Base.connected_to(role: :reading) { issue.reactions_count }.values.sum

      increment_bytesize(@hash.to_s)
      @hash[:comments] = issue_comments + review_comments

      GitHub.dogstats.increment("pull_request.indexing_commit_info_missing", tags: datadog_tags(index)) if @hash[:commits].nil?

      # the `total_comments` method is used here to keep the data in
      # Elasticsearch congruent with the results we present via the
      # app/view_models/issues/issue_list_item.rb `comment_count` method
      # see https://github.com/github/github/pull/58080
      @hash[:num_comments] = pr.total_comments

      @hash[:num_interactions] = @hash[:num_comments] + @hash[:num_reactions]

      @hash
    end

    # Internal: Generate information about all the commits in this pull
    # request.
    #
    # Returns a Hash containing summarized commit information.
    sig { returns(Hash) }
    def commit_info
      hash = {
        additions: nil,
        deletions: nil,
        changed_files: nil,
        commits: nil,
        num_commits: nil,
      }

      return hash unless pr = model
      return hash unless repository = pr.repository

      git_dependency(default: hash) do
        if repository.exists_on_disk?
          historical_comparison = pr.historical_comparison
          diffs = historical_comparison.diffs

          if diffs.available?
            hash[:additions] = diffs.additions
            hash[:deletions] = diffs.deletions
            hash[:changed_files] = diffs.size
          end

          hash[:commits] = pr.linked_commit_ids(limit: 1000)
          hash[:num_commits] = historical_comparison.total_commits
        end

        hash
      end
    end

    # Internal: Take all the issue comments and review comments for the pull
    # request and return them in a single array. Each comment is converted
    # into a Hash and added to the array.
    #
    # Returns an array of comments for the pull request.
    sig { returns(T::Array[Hash]) }
    def issue_comments
      return [] unless pr = model
      return [] unless issue = pr.issue

      comments = map_with_truncation(issue.comments.not_spammy.limit(::Issue::COMMENT_LIMIT)) do |comment|
        {
          comment_id: comment.id,
          comment_type: "issue",
          body: ::Search.clean_and_sanitize(comment.body),
          author_id: comment.user_id,
          created_at: comment.created_at,
          updated_at: comment.updated_at,
          reactions: ActiveRecord::Base.connected_to(role: :reading) { comment.reactions_count },
          dead: false,
        }
      end

      comments.compact
    end

    REVIEW_COMMENT_BATCH_SIZE = 100
    def comments_with_batching(pr)
      comments = T.let([], T::Array[Hash])

      pr.review_comments.includes(:pull_request_review_thread).not_spammy.find_in_batches(batch_size: REVIEW_COMMENT_BATCH_SIZE) do |batch|
        break if bytesize_estimate >= max_document_size

        comments += map_with_truncation(batch.reject(&:pending?)) do |comment|
          begin
            {
              comment_id: comment.id,
              comment_type: "review",
              body: ::Search.clean_and_sanitize(comment.body),
              author_id: comment.user_id,
              created_at: comment.created_at,
              updated_at: comment.updated_at,
              reactions: ActiveRecord::Base.connected_to(role: :reading) { comment.reactions_count },

              # TODO once we transitioned to the PRRC#outdated? attribute, use it here
              dead: !comment.live?,
            }
          rescue => e
            Failbot.report(e)
          end
        end
      end

      comments += map_with_truncation(pr.reviews.reject(&:pending?)) do |review|
        {
          comment_id: review.id,
          comment_type: "review_body",
          body: ::Search.clean_and_sanitize(review.body),
          author_id: review.user_id,
          created_at: review.created_at,
        }
      end
    end

    def comments_with_ruby_filtering(pr)
      comments = map_with_truncation(pr.review_comments.includes(:pull_request_review_thread).not_spammy.reject(&:pending?)) do |comment|
        {
          comment_id: comment.id,
          comment_type: "review",
          body: ::Search.clean_and_sanitize(comment.body),
          author_id: comment.user_id,
          created_at: comment.created_at,
          updated_at: comment.updated_at,
          reactions: ActiveRecord::Base.connected_to(role: :reading) { comment.reactions_count },

          # TODO once we transitioned to the PRRC#outdated? attribute, use it here
          dead: !comment.live?,
        }
      end

      comments += map_with_truncation(pr.reviews.reject(&:pending?)) do |review|
        {
          comment_id: review.id,
          comment_type: "review_body",
          body: ::Search.clean_and_sanitize(review.body),
          author_id: review.user_id,
          created_at: review.created_at,
        }
      end
    end

    # Internal: Take all the issue comments and review comments for the pull
    # request and return them in a single array. Each comment is converted
    # into a Hash and added to the array.
    #
    # Returns an array of comments for the pull request.
    sig { returns(T::Array[Hash]) }
    def review_comments
      return [] unless pr = model

      if pr.repository&.feature_enabled?(:pull_request_review_comments_batching)
        comments_with_batching(pr)
      else
        comments_with_ruby_filtering(pr)
      end
    end

    def map_with_truncation(items)
      items.each_with_object([]) do |item, memo|
        hash = yield item

        str = hash.to_s

        if will_exceed_max_document_size(str)
          GitHub.dogstats.increment "pull_request.indexing.truncated", tags: datadog_tags(index)
          break memo
        else
          increment_bytesize(str)
          memo << hash
        end
      end
    end

    sig { params(str: String).returns(T::Boolean) }
    def will_exceed_max_document_size(str)
      bytesize_estimate + str.bytesize > max_document_size
    end

    sig { params(str: String).void }
    def increment_bytesize(str)
      self.bytesize_estimate += str.bytesize
    end

    # Attempt to call code referencing `git-systems` and handle the potential errors thrown. Exceptions are bubbled up
    # to the AddToSearchIndexJob where we retry and set `skip_commit_info_on_failure`.
    def git_dependency(default: nil)
      yield
    rescue GitRPC::Error, ::Repository::CommandFailed, GitHub::DGit::Error, GitHub::Spokes::ClientError, SpokesAPI::Error => err
      tags = datadog_tags(index)
      tags << "error:#{err.class}"

      if model = self.model
        tags << "pr:delete_after_merge" if model.head_repository&.delete_branch_on_merge?
        if model.merged?
          tags << "pr:merged"
        elsif model.closed?
          tags << "pr:closed"
        elsif tags << "pr:open"
        end

        age = Time.now - T.must(model.created_at)

        if age < 1.day
          tags << "age:1d"
        elsif age < 1.week
          tags << "age:1w"
        elsif age < 1.month
          tags << "age:1m"
        elsif age < 6.months
          tags << "age:6m"
        elsif age < 1.year
          tags << "age:1y"
        else
          tags << "age:1y+"
        end
      end

      GitHub.dogstats.increment("pull_request.indexing_commit_info_failed", tags:)

      if !skip_commit_info_on_failure
        raise MissingCommitInfo, err.message
      else
        default
      end
    end
  end  # PullRequest
end  # Elastomer::Index
