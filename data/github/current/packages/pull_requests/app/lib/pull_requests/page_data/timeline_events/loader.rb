# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TimelineEvents
  # Normalizes a batch of pull-request activity records into a
  # single `Event` struct, shared by `Timeline::Loader` and
  # `CatchUpSnapshot::Loader` so both surfaces extract IDs, timestamps, users,
  # and per-type metadata the same way. Associations are preloaded in
  # `preload_batch` to avoid N+1s. Unknown types are dropped.
  #
  # Timeline events (from PullRequests::Timeline::PullRequestTimeline):
  #   IssueComment, IssueEvent, PullRequestReview, PullRequestReviewThread,
  #   Platform::Models::PullRequestCommit, CrossReference,
  #   PullRequestRevisionMarker
  #
  # Non-timeline events (loaded separately by callers):
  #   IssueEdit (description edits from Issue#user_content_edits)
  class Loader
    class User < T::Struct
      const :id, Integer
      const :display_login, String
      const :avatar_url, String
    end

    class Event < T::Struct
      const :id, String
      const :type, String
      const :timestamp, T.nilable(Time)
      const :user, T.nilable(User)
      const :additional_info, T::Hash[Symbol, T.untyped]
    end

    sig { returns(T.nilable(::User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { params(current_user: T.nilable(::User), pull_request: PullRequest).void }
    def initialize(current_user:, pull_request:)
      @current_user = current_user
      @pull_request = pull_request
      @agentic_apps_cache = T.let({}, T::Hash[Integer, T.untyped])
    end

    # Load multiple timeline items into Event structs
    # Automatically preloads associations to avoid N+1 queries
    sig { params(items: T::Array[T.untyped]).returns(T::Array[Event]) }
    def load(items)
      return [] if items.empty?

      # Preload associations to avoid N+1 queries
      preload_batch(items)

      # Load each item into an Event struct
      items.map { |item| load_single(item) }.compact
    end

    private

    # Preload associations for a batch of timeline items to avoid N+1 queries
    sig { params(items: T::Array[T.untyped]).void }
    def preload_batch(items)
      # Preload review associations
      reviews = items.grep(PullRequestReview)
      if reviews.any?
        ActiveRecord::Associations::Preloader.new(
          records: reviews,
          associations: [:review_comments]
        ).call
        GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_on_behalf_of_visible_teams_for, @current_user)

        dismissed_reviews = reviews.select(&:dismissed?)
        Prelude::Preloader.new(dismissed_reviews).fetch(:dismissed_review_state) if dismissed_reviews.any?
      end

      # Preload issue event associations (for review requests and assignments)
      issue_events = items.grep(IssueEvent)
      if issue_events.any?
        ActiveRecord::Associations::Preloader.new(
          records: issue_events,
          associations: [{ issue_event_detail: :subject }, :actor]
        ).call
      end

      # Preload review thread comments
      review_threads = items.grep(PullRequestReviewThread)
      if review_threads.any?
        ActiveRecord::Associations::Preloader.new(
          records: review_threads,
          associations: [{ review_comments: :user }]
        ).call
      end
    end

    sig { params(item: T.untyped).returns(T.nilable(Event)) }
    def load_single(item)
      id = extract_id(item)
      timestamp = extract_timestamp(item)
      user = extract_user(item)

      case item
      when IssueComment
        build_issue_comment_item(item, id, timestamp, user)
      when IssueEvent
        build_issue_event_item(item, id, timestamp, user)
      when PullRequestReview
        build_pull_request_review_item(item, id, timestamp, user)
      when Platform::Models::PullRequestCommit
        build_pull_request_commit_item(item, id, timestamp, user)
      when CrossReference
        Event.new(id: id, type: "CrossReference", timestamp: timestamp, user: user, additional_info: {})
      when PullRequestReviewThread
        Event.new(id: id, type: "PullRequestReviewThread", timestamp: timestamp, user: user, additional_info: {})
      when PullRequestRevisionMarker
        Event.new(id: id, type: "PullRequestRevisionMarker", timestamp: timestamp, user: nil,
          additional_info: { lastSeenCommitOid: item.last_seen_commit_oid })
      when IssueEdit
        # Description updates
        Event.new(id: id, type: "IssueEdit", timestamp: timestamp, user: user, additional_info: {})
      else
        nil
      end
    end


    sig { params(item: T.untyped).returns(T.nilable(Time)) }
    def extract_timestamp(item)
      case item
      when PullRequestReviewThread
        item.comments&.first&.created_at
      when PullRequestReview
        item.submitted_at
      when Platform::Models::PullRequestCommit
        item.commit.committed_date if item.commit.respond_to?(:committed_date)
      when IssueEdit
        item.edited_at
      else
        # Fallback for IssueComment, IssueEvent, CrossReference,
        # PullRequestRevisionMarker, and any other type with a created_at.
        item.created_at if item.respond_to?(:created_at)
      end
    end

    sig { params(item: T.untyped).returns(T.nilable(User)) }
    def extract_user(item)
      # Special case for PullRequestReviewThread: use first comment's user
      if item.is_a?(PullRequestReviewThread)
        first_comment = item.comments&.first
        return extract_user_data(first_comment) if first_comment
      end

      # Special case for assigned/unassigned events: use the subject instead of the actor
      if item.is_a?(IssueEvent) && (item.event == "assigned" || item.event == "unassigned")
        subject_user = item.issue_event_detail&.subject
        return subject_user.is_a?(::User) ? build_user(subject_user) : nil
      end

      extract_user_data(item)
    end

    sig { params(item: T.untyped).returns(T.nilable(User)) }
    def extract_user_data(item)
      actor = extract_actor(item)
      return nil unless actor

      build_user(actor)
    end

    # Returns the underlying ::User (or Bot) record that authored/triggered the
    # given timeline item, without wrapping it in our Event-payload User struct.
    sig { params(item: T.untyped).returns(T.nilable(::User)) }
    def extract_actor(item)
      case item
      when IssueComment, PullRequestReview, PullRequestReviewComment
        item.user
      when IssueEvent, CrossReference
        item.actor
      when Platform::Models::PullRequestCommit
        item.commit.author if item.commit.author.is_a?(::User)
      when IssueEdit
        item.editor
      end
    end

    # Builds the Event-payload User struct from a ::User (or Bot) record.
    sig { params(actor: ::User).returns(User) }
    def build_user(actor)
      avatar_url = actor.primary_avatar_url || ::User::AvatarList.default_image_url("gravatar-user-420")

      display_login = if actor.is_a?(Bot)
        bot_display_name(actor)
      else
        actor.display_login
      end

      User.new(
        id: actor.id,
        display_login: display_login,
        avatar_url: avatar_url
      )
    end

    sig { params(item: T.untyped).returns(String) }
    def extract_id(item)
      type_prefix = item.class.name&.demodulize || "Unknown"
      raw_id = case item
      when PullRequestRevisionMarker
        item.global_id
      when Platform::Models::PullRequestCommit
        item.oid.to_s
      when IssueComment, IssueEvent, PullRequestReview, CrossReference, PullRequestReviewThread, IssueEdit
        item.id.to_s
      else
        SecureRandom.uuid
      end
      # Prefix ids to prevent collisions across different types
      "#{type_prefix}_#{raw_id}"
    end

    sig { params(item: IssueComment, id: String, timestamp: T.nilable(Time), user: T.nilable(User)).returns(Event) }
    def build_issue_comment_item(item, id, timestamp, user)
      Event.new(
        id: id,
        type: "IssueComment",
        timestamp: timestamp,
        user: user,
        additional_info: { commentId: item.id }
      )
    end

    sig { params(item: IssueEvent, id: String, timestamp: T.nilable(Time), user: T.nilable(User)).returns(Event) }
    def build_issue_event_item(item, id, timestamp, user)
      info = { eventType: item.event }
      detail = item.issue_event_detail

      case item.event
      when "assigned", "unassigned"
        # For assigned/unassigned events, include assignee info
        actor = item.actor
        info[:assigneeLogin] = actor.display_login if actor.is_a?(::User)
      when "labeled", "unlabeled"
        # For label events, include both name and color
        label = { name: detail&.label_name, color: detail&.label_color }.compact
        info[:label] = label if label.any?
      when "review_requested", "review_request_removed"
        # For review request events, distinguish between user and team reviewers
        subject = detail&.subject
        if subject.is_a?(::User)
          info[:reviewerLogin] = subject.display_login
          # Provide requestedReviewer for backward compatibility with catch_up_snapshot
          # TODO: Migrate catch_up_snapshot to use reviewerLogin instead
          info[:requestedReviewer] = subject.display_login
        elsif subject.is_a?(Team)
          info[:reviewerTeamSlug] = subject.slug
          # Provide requestedReviewer for backward compatibility with catch_up_snapshot
          # TODO: Migrate catch_up_snapshot to use reviewerTeamSlug instead
          info[:requestedReviewer] = subject.slug
        end
      when "review_dismissed"
        info[:dismissalMessage] = detail&.message
      when "merged"
        info[:commitOid] = item.commit_id
      when "head_ref_force_pushed", "base_ref_force_pushed"
        info[:beforeCommitOid] = detail&.before_commit_oid
        info[:afterCommitOid] = detail&.after_commit_oid
        info[:ref] = detail&.ref
      when "renamed"
        info[:previousTitle] = detail&.title_was
        info[:newTitle] = detail&.title_is
      when "closed"
        info[:stateReason] = detail&.state_reason
      when "locked"
        info[:lockReason] = detail&.lock_reason
      end

      Event.new(
        id: id,
        type: "IssueEvent",
        timestamp: timestamp,
        user: user,
        additional_info: info.compact
      )
    end

    sig { params(item: PullRequestReview, id: String, timestamp: T.nilable(Time), user: T.nilable(User)).returns(Event) }
    def build_pull_request_review_item(item, id, timestamp, user)
      info = {
        state: PullRequestReview.state_name(item.state),
        reviewId: item.id,
      }

      # Comment count for the review (default to 0 if not available)
      info[:commentCount] = if item.respond_to?(:review_comments)
        item.review_comments.size
      else
        0
      end

      # Is the reviewer the PR author?
      info[:isAuthor] = item.user_id == @pull_request.user_id

      # Reviewer type (user/automated/copilot/code_scanning)
      info[:reviewerType] = item.variant_type

      # Does the reviewer have write access?
      info[:qualifiedReviewer] = item.qualified_reviewer?

      # Dismissed state (if the review was dismissed)
      info[:dismissedState] = if item.dismissed?
        raw = item.dismissed_review_state
        PullRequestReview.state_name(raw) if raw
      else
        nil
      end

      # Check if this review fulfilled any team review requests (default to nil if none)
      info[:requestedReviewerTeams] = if item.respond_to?(:prelude_on_behalf_of_visible_teams_for)
        on_behalf_of_teams = item.prelude_on_behalf_of_visible_teams_for(@current_user)
        on_behalf_of_teams.any? ? on_behalf_of_teams.map(&:name) : nil
      else
        nil
      end

      # Check if the review was submitted on the current head commit (default to nil)
      info[:reviewedCommitOid] = if item.respond_to?(:pull_request_has_changed?) && item.pull_request_has_changed?
        item.head_sha
      else
        nil
      end

      Event.new(
        id: id,
        type: "PullRequestReview",
        timestamp: timestamp,
        user: user,
        additional_info: info.compact
      )
    end

    sig { params(item: Platform::Models::PullRequestCommit, id: String, timestamp: T.nilable(Time), user: T.nilable(User)).returns(Event) }
    def build_pull_request_commit_item(item, id, timestamp, user)
      info = {
        sha: item.oid,
        shortMessageText: item.commit.message&.lines&.first&.strip,
      }

      # Add baseSha (parent commit) for first commit in range
      # Used by catch_up_snapshot to build commit range links
      if item.commit.parent_oids.any?
        info[:baseSha] = item.commit.parent_oids.first
      end

      Event.new(
        id: id,
        type: "PullRequestCommit",
        timestamp: timestamp,
        user: user,
        additional_info: info.compact
      )
    end

    sig { params(bot: Bot).returns(String) }
    def bot_display_name(bot)
      # For AgenticApp bots, use the display_name (e.g., "Claude")
      # For regular bots, use the display_login (includes [bot] suffix)
      agentic_app = agentic_app_for_bot(bot)
      agentic_app ? agentic_app.display_name : bot.display_login
    end

    sig { params(bot: Bot).returns(T.untyped) }
    def agentic_app_for_bot(bot)
      return @agentic_apps_cache[bot.id] if @agentic_apps_cache.key?(bot.id)

      @agentic_apps_cache[bot.id] = bot.async_agentic_app.sync
    end
  end
end
