# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview
  class Loader
    include PullRequests::PageData::Telemetry

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class SinceSource < T::Enum
      enums do
        Created = new("created")
        LastReview = new("last_review")
        LastInteracted = new("last_interacted")
        ReadyForReview = new("ready_for_review")
      end
    end

    class Candidate < T::Struct
      const :timestamp, Time
      const :source, SinceSource
    end

    class SinceSelector < T::Struct
      const :timestamp, Time
      const :source, SinceSource
      const :selected, T::Boolean, default: false
    end

    class FileSummary < T::Struct
      const :path, String
      const :additions, Integer
      const :deletions, Integer
    end

    class ChangeSummary < T::Struct
      const :name, String
      const :file_summaries, T::Array[FileSummary]
    end

    class CopilotReviewSummary < T::Struct
      const :review_id, Integer
      const :state, String # "commented" or "changes_requested"
      const :submitted_at, Time
      const :body_html, String
      const :comment_count, Integer
      const :reviewer_login, String
      const :reviewer_avatar_url, String
      const :url, String
    end

    class OverviewData < T::Struct
      const :description, T.nilable(String)
      const :description_text, T.nilable(String)
      const :change_highlights, T::Array[ChangeSummary]
      const :since_selectors, T::Array[SinceSelector]
      const :last_activity_timestamp, Time
      const :copilot_review_summary, T.nilable(CopilotReviewSummary)
    end

    sig { params(pull_request: PullRequest, cap_filter: T.nilable(ConditionalAccess::Web::Filter), current_user: T.nilable(::User)).returns(OverviewData) }
    def self.load(pull_request:, cap_filter:, current_user: nil)
      new(pull_request:, cap_filter:, current_user:).load
    end

    sig { params(pull_request: PullRequest, cap_filter: T.nilable(ConditionalAccess::Web::Filter), current_user: T.nilable(::User)).void }
    def initialize(pull_request:, cap_filter:, current_user: nil)
      @pull_request = pull_request
      @current_user = current_user
      @cap_filter = cap_filter
    end

    sig { returns(OverviewData) }
    def load
      description = load_description

      OverviewData.new(
        description: description.body_html,
        description_text: description.body,
        change_highlights: load_change_highlights,
        since_selectors: build_since_selectors,
        last_activity_timestamp: @pull_request.issue&.updated_at || @pull_request.updated_at,
        copilot_review_summary: load_copilot_review_summary,
      )
    end

    private

    sig { returns(PullRequests::PageData::Description::Loader::DescriptionData) }
    def load_description
      PullRequests::PageData::Description::Loader.load(
        pull_request: @pull_request,
        current_user: @current_user,
        cap_filter: @cap_filter,
      )
    end

    sig { returns(T.nilable(CopilotReviewSummary)) }
    def load_copilot_review_summary
      copilot_bot_user_id = PullRequestReview.copilot_pr_reviewer_bot_user_id
      return nil unless copilot_bot_user_id

      review = @pull_request.reviews
        .where(user_id: copilot_bot_user_id)
        .where.not(submitted_at: nil)
        .where(state: [
          PullRequestReview.state_value(:commented),
          PullRequestReview.state_value(:changes_requested),
        ])
        .order(submitted_at: :desc)
        .first
      return nil unless review

      reviewer = review.user
      return nil unless reviewer

      state = review.current_state.name == :changes_requested ? "changes_requested" : "commented"

      CopilotReviewSummary.new(
        review_id: review.id,
        state: state,
        submitted_at: review.submitted_at || review.created_at,
        body_html: review.body_html.to_s,
        comment_count: review.review_comments.count,
        reviewer_login: reviewer.display_login,
        reviewer_avatar_url: reviewer.primary_avatar_url(40),
        url: review.permalink(include_host: false),
      )
    end

    sig { returns(T::Array[ChangeSummary]) }
    def load_change_highlights
      return [] unless FeatureFlag.vexi.enabled?(:prs_overview_change_highlights, @pull_request.repository, default: false)

      change_groups = @pull_request.current_change_groups.order(priority: :desc).to_a
      change_groups.map do |group|
        file_summaries = build_file_summaries(group.parsed_hunk_positions)
        ChangeSummary.new(
          name: group.name,
          file_summaries: file_summaries,
        )
      end
    end

    sig { returns(T::Array[SinceSelector]) }
    def build_since_selectors
      candidates = T.let([], T::Array[Candidate])

      # Always available: since PR was created
      candidates << Candidate.new(timestamp: @pull_request.created_at, source: SinceSource::Created)

      if @current_user
        # Since user's last review
        last_review = @pull_request.reviews.where(user_id: @current_user.id).where.not(submitted_at: nil).order(submitted_at: :desc).first
        candidates << Candidate.new(timestamp: last_review.submitted_at, source: SinceSource::LastReview) if last_review

        # Since user last interacted (comments)
        last_issue_comment = @pull_request.issue&.comments&.where(user_id: @current_user.id)&.reorder(created_at: :desc)&.first
        last_review_comment = @pull_request.review_comments.where(user_id: @current_user.id).order(created_at: :desc).first

        interaction_timestamps = T.let([], T::Array[Time])
        interaction_timestamps << last_issue_comment.created_at if last_issue_comment
        interaction_timestamps << last_review_comment.created_at if last_review_comment

        if interaction_timestamps.any?
          latest_interaction = T.must(interaction_timestamps.max)
          candidates << Candidate.new(timestamp: latest_interaction, source: SinceSource::LastInteracted)
        end
      end

      # Since PR was marked ready for review (if applicable)
      issue_id = @pull_request.issue&.id
      if issue_id && !@pull_request.draft?
        ready_for_review_event = IssueEvent.where(issue_id: issue_id, event: "ready_for_review").order(created_at: :desc).first
        if ready_for_review_event
          candidates << Candidate.new(timestamp: ready_for_review_event.created_at, source: SinceSource::ReadyForReview)
        end
      end

      # Sort by timestamp desc and mark the most recent one as selected
      candidates.sort_by! { |c| -c.timestamp.to_i }
      selected_source = candidates.max_by { |c| c.timestamp }&.source

      candidates.map do |candidate|
        SinceSelector.new(
          timestamp: candidate.timestamp,
          source: candidate.source,
          selected: candidate.source == selected_source
        )
      end
    end

    sig { params(parsed_hunk_positions: T::Array[PullRequests::ChangeGroup::HunkPosition]).returns(T::Array[FileSummary]) }
    def build_file_summaries(parsed_hunk_positions)
      file_stats = T.let({}, T::Hash[String, { additions: Integer, deletions: Integer }])

      parsed_hunk_positions.each do |hunk_position|
        path = hunk_position.path
        stats = file_stats[path] ||= { additions: 0, deletions: 0 }
        added = hunk_position.added_lines
        removed = hunk_position.removed_lines
        stats[:additions] += added&.size || 0
        stats[:deletions] += removed&.size || 0
      end

      file_stats.map do |path, stats|
        FileSummary.new(
          path: path,
          additions: stats[:additions],
          deletions: stats[:deletions],
        )
      end
    end
  end
end
