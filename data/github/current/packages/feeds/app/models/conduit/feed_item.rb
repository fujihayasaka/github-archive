# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem
    include GitHub::Memoizer

    ITEM_TYPES = {
      # Release
      TwirpHelper.published_release_key               => PublishedRelease,

      # Discussion
      TwirpHelper.created_discussion_key              => CreatedDiscussion,

      # Sponsor
      TwirpHelper.near_sponsors_goal_key              => NearSponsorsGoal,
      TwirpHelper.sponsorable_user_key                => SponsorableUser,
      TwirpHelper.sponsored_user_key                  => SponsoredUser,

      # User
      TwirpHelper.added_to_list_key                   => AddedToList,
      TwirpHelper.follow_recommendation_key           => FollowRecommendation,
      TwirpHelper.followed_user_key                   => FollowedUser,

      # FeedPost
      TwirpHelper.created_feed_post_key               => CreatedFeedPost,

      # Issue
      TwirpHelper.assigned_issue_key                  => AssignedIssue,
      TwirpHelper.closed_issue_key                    => ClosedIssue,
      TwirpHelper.created_issue_key                   => CreatedIssue,
      TwirpHelper.labeled_issue_key                   => LabeledIssue,
      TwirpHelper.reopened_issue_key                  => ReopenedIssue,
      TwirpHelper.unassigned_issue_key                => UnassignedIssue,
      TwirpHelper.unlabeled_issue_key                 => UnlabeledIssue,

      # IssueComment
      TwirpHelper.created_issue_comment_key           => CommentedIssue,

      # Pull Request
      TwirpHelper.assigned_pull_request_key           => AssignedPullRequest,
      TwirpHelper.closed_pull_request_key             => ClosedPullRequest,
      TwirpHelper.created_pull_request_key            => CreatedPullRequest,
      TwirpHelper.labeled_pull_request_key            => LabeledPullRequest,
      TwirpHelper.merged_pull_request_key             => MergedPullRequest,
      TwirpHelper.reopened_pull_request_key           => ReopenedPullRequest,
      TwirpHelper.requested_review_pull_request_key   => RequestedReviewPullRequest,
      TwirpHelper.rerequested_review_pull_request_key => RerequestedReviewPullRequest,
      TwirpHelper.unassigned_pull_request_key         => UnassignedPullRequest,
      TwirpHelper.unlabeled_pull_request_key          => UnlabeledPullRequest,
      TwirpHelper.unrequested_review_pull_request_key => UnrequestedReviewPullRequest,

      # PullRequestComment
      TwirpHelper.created_pull_request_comment_key    => CommentedPullRequest,

      # Repository
      TwirpHelper.created_repository_key              => CreatedRepository,
      TwirpHelper.forked_repository_key               => ForkedRepository,
      TwirpHelper.member_add_to_repository_key        => MemberAddToRepository,
      TwirpHelper.private_to_public_repository_key    => PrivateToPublicRepository,
      TwirpHelper.repository_recommendation_key       => RepositoryRecommendation,
      TwirpHelper.starred_repository_key              => StarredRepository,
      TwirpHelper.trending_repository_key             => TrendingRepository,

      # PullRequestReview
      TwirpHelper.created_pull_request_review_key     => CreatedPullRequestReview,
      TwirpHelper.dismissed_pull_request_review_key   => DismissedPullRequestReview,
      TwirpHelper.updated_pull_request_review_key     => UpdatedPullRequestReview,

      # PullRequestReviewComment
      TwirpHelper.created_pr_review_comment_key       => CreatedPullRequestReviewComment,

      # CommitComment
      TwirpHelper.created_commit_comment_key          => CommentedCommit,

      # Push
      TwirpHelper.published_push_key                  => PushEvent,

      # Wiki
      TwirpHelper.published_wiki_key                  => PublishedWiki,
    }

    ROLLUP_ITEM_TYPES = [
      StarredRepository,
      FollowedUser,
      PublishedRelease,
      SponsoredUser,
      CreatedRepository,
      ForkedRepository,
      AddedToList,
      CreatedDiscussion,
      TrendingRepository,
      FollowRecommendation,
      RepositoryRecommendation,
      ClosedPullRequest,
      CreatedIssue,
      CreatedPullRequest,
      ReopenedIssue,
      ReopenedPullRequest,
      MemberAddToRepository,
      CommentedPullRequest,
      CommentedIssue,
      ClosedIssue,
      CreatePush,
      DeletePush,
      PushEvent,
    ]

    ACTOR_REASON = {
      self: "You're seeing this because you are %s",
      followed: "You're seeing this because you follow %s",
      sponsored: "You're seeing this because you sponsor %s",
      collaborated: "You're seeing this because you collaborated with %s",
    }.freeze

    SUBJECT_REASON = {
      starred: "You're seeing this because you starred %s",
      committed: "You're seeing this because you've contributed to %s",
      trending: "You're seeing this based on GitHub-wide trends.",
    }.freeze

    REASON_PRIORITY = %w[self starred followed sponsored collaborated committed trending].freeze

    RECOMMENDATION_REASON = "You're seeing this because of your activity."

    delegate :action, :related_by, :user_hidden, :event_id, :identifier, :gatherer, to: :twirp_item
    alias_method :user_hidden?, :user_hidden

    def self.multiple_target_for_conditional_access(resources)
      resources.each_with_object({}) { |resource, h| h[resource] = resource.target_for_conditional_access }
    end

    attr_accessor :idx, :sub_idx
    alias_method(:id, :idx)
    attr_reader :actor, :subject, :related_items, :viewer, :twirp_item

    attr_reader :feed
    private :feed
    delegate :profile_activity_context?, :sticky_announcements_enabled?, :request_id,
      :assignment_context, :variants, :ranking_model_id, :list_context?,
      to: :feed, allow_nil: true

    attr_reader :label

    include TwirpHelper
    include AnalyticsHelper

    # Public: Given a twirp item, build a feed item
    #
    # twirp_item: An instance of MonolithTwirp::Conduit::Feeds::V1::FeedItem
    # actor: A user
    # subject: A subject
    # idx: An integer representing the index for the feed item
    # sub_idx: An integer representing the index for the feed item when within a rollup
    # feed: The feed object in which this item exists
    # related_items: An array of related feed items
    def self.build(
      twirp_item,
      actor:,
      subject:,
      idx: nil,
      sub_idx: nil,
      related_items: [],
      feed: nil,
      viewer: nil
    )
      return unless subject

      item_key = TwirpHelper.key_for_item(twirp_item)
      return unless actor || allows_nil_actor?(item_key)
      # Set nil PushEvent actor to the repository owner or creator
      if !actor && item_key == TwirpHelper.published_push_key
        actor = subject&.repository.owner || subject&.repository.created_by_user
      end

      if GitHub.flipper[:turn_off_jazz_user_repository_recommendations].enabled?
        return if item_key == TwirpHelper.repository_recommendation_key
      end

      found_item = ITEM_TYPES[item_key]
      return unless found_item

      found_item.new(
        twirp_item,
        actor: actor,
        subject: subject,
        idx: idx,
        sub_idx: sub_idx,
        related_items: related_items,
        feed: feed,
        viewer: viewer,
      )
    end

    # twirp_item: A MonolithTwirp::Conduit::Feeds::V1::FeedItem
    # actor: A User instance
    # subject: A PullRequest, Repository, Discussion, Release, or User instance
    # idx: An integer representing the index for the feed item
    # related_items: An array of related feed items
    def initialize(twirp_item, actor:, subject:, idx: nil, sub_idx: nil, related_items: [], feed: nil, viewer: nil)
      @twirp_item = twirp_item
      @actor = actor
      @subject = subject
      @idx = idx
      @sub_idx = sub_idx
      @related_items = related_items
      @feed = feed
      @viewer = viewer
    end

    def actor_id
      actor&.id
    end

    def subject_id
      subject.id
    end

    def event_hmac
      Conduit.hmac_for_event_id(event_id.to_s)
    end

    def item_key
      TwirpHelper.key_for_item(twirp_item)
    end

    def action_string
      raise NotImplementedError.new("Expected subclass to implement #{__method__}")
    end

    def created_at
      if twirp_item.time.present?
        Time.at(twirp_item.time.seconds)
      end
    end

    def last_modified_at
      created_at
    end

    def event_type
      twirp_item.event_type
    end

    def user_event?
      item_key == TwirpHelper.sponsored_user_key ||
      item_key == TwirpHelper.followed_user_key
    end

    def discussion_event?
      item_key == TwirpHelper.created_discussion_key
    end

    def release_event?
      item_key == TwirpHelper.published_release_key
    end

    def feed_post_event?
      item_key == TwirpHelper.created_feed_post_key
    end

    def repo_event?
      item_key == TwirpHelper.private_to_public_repository_key ||
      item_key == TwirpHelper.created_repository_key ||
      item_key == TwirpHelper.repository_recommendation_key ||
      item_key == TwirpHelper.forked_repository_key ||
      item_key == TwirpHelper.starred_repository_key ||
      item_key == TwirpHelper.added_to_list_key
    end

    def newly_sponsorable_event?
      item_key == TwirpHelper.sponsorable_user_key
    end

    def near_sponsors_goal_event?
      item_key == TwirpHelper.near_sponsors_goal_key
    end

    def pull_request_event?
      item_key.include?(TwirpHelper.pull_request_subject_type.to_s)
    end

    def follow_recommendation_event?
      item_key == TwirpHelper.follow_recommendation_key
    end

    def recommendation_event?
      follow_recommendation_event? ||
      item_key == TwirpHelper.repository_recommendation_key
    end

    def trending_repository_event?
      item_key == TwirpHelper.trending_repository_key
    end

    def issue_event?
      item_key.include?(TwirpHelper.issue_subject_type.to_s)
    end

    def push_event?
      item_key == TwirpHelper.published_push_key
    end

    def rollup?
      related_items.any? &&
      ROLLUP_ITEM_TYPES.include?(self.class)
    end

    memoize def total_related_items
      related_items.size
    end

    memoize def rollup_item_count
      total_related_items + 1 # all related items plus the parent item
    end

    def description
      raise NotImplementedError.new("Expected subclass #{self.class.name} to implement #{__method__}")
    end

    def api_type
      raise NotImplementedError.new("Expected subclass #{self.class.name} to implement #{__method__}")
    end

    def payload
      raise NotImplementedError.new("Expected subclass #{self.class.name} to implement #{__method__}")
    end

    # Parses the given ref for the event payload.
    def parse_ref(ref)
      ref&.split("/", 3)&.last
    end

    def repository
      nil
    end

    def topic
      nil
    end

    def self.supports_graphql?
      true
    end

    def reason
      twirp_item.relationship || ""
    end

    def actor_relationship(relationships)
      return :self if relationships.include?("self")
      return :followed if relationships.include?("followed")
      return :sponsored if relationships.include?("sponsored")
      :collaborated if relationships.include?("collaborated")
    end

    memoize def reason_message
      return if reason.blank?

      relationships = reason.split(",").map(&:downcase)
      relationship = relationships.sort_by do |rel|
        REASON_PRIORITY.index(rel) || Float::INFINITY
      end.first&.to_sym

      @reason_message =
      if recommendation_event?
        RECOMMENDATION_REASON
      elsif ACTOR_REASON.key?(relationship) && actor.present?
        relationship = actor_relationship(relationships)
        ACTOR_REASON[relationship] % [actor.display_login]
      elsif SUBJECT_REASON.key?(relationship) && topic.present?
        SUBJECT_REASON[relationship] % [topic.name]
      elsif SUBJECT_REASON.key?(relationship) && repository.present?
        SUBJECT_REASON[relationship] % [repository.name_with_display_owner]
      else
        nil
      end
    end

    def source
      # displayable string of the source of this event
      # such as a repository name with owner for a release or discussion, etc.,
      # or an actor user name for a user event (follow, sponsor, etc.)
      raise NotImplementedError.new("Expected subclass to implement #{__method__}")
    end

    def content_type
      return "added-to-list repositories" if self.is_a?(Conduit::FeedItem::AddedToList)

      self.class.name&.underscore.split("/").last.gsub("_", " ")
    end

    def contains_viewer?
      return false unless viewer

      subject_is_viewer? ||
        related_items.any? { |r_item| r_item.contains_viewer? }
    end

    def subject_is_viewer?
      subject.id == viewer&.id
    end

    # The subjects to display in a the rollup heading
    #
    # If there's 1 related item and it's the viewer (viewer card will never be on top),
    # use the top card subject in the header. Otherwise use,
    def heading_subjects
      if total_related_items == 1 && contains_viewer?
        [subject]
      else
        related_items.filter_map { |item| item.subject unless item.subject_is_viewer? }
      end
    end

    def display_subject
      return subject unless user_event?

      if subject_is_viewer?
        actor
      else
        subject
      end
    end

    def render?
      return true unless user_event?
      return true unless related_item?

      !subject_is_viewer?
    end

    def related_item?
      (sub_idx && sub_idx > 0) && idx
    end

    def show_related_items?
      return true unless user_event?

      !(total_related_items == 1 && contains_viewer?)
    end

    def actor_reason?
      return unless reason&.present?
      relationship = reason.split(",").first.downcase.to_sym

      ACTOR_REASON.key?(relationship) && actor.present?
    end

    def deletable_by?(viewer)
      return unless feed_post_event?
      subject.deletable_by?(viewer)
    end

    def adminable_by?(viewer)
      viewer == actor
    end

    def announcement?
      gatherer == "announcements"
    end
    alias_method :dismissible?, :announcement?

    def apply_label(label)
      @label = label
    end

    def target_for_conditional_access
      return subject&.repository&.target_for_conditional_access if push_event?

      subject&.target_for_conditional_access
    end

    def self.allows_nil_actor?(item_key)
      [
        TwirpHelper.repository_recommendation_key,
        TwirpHelper.trending_repository_key,
        TwirpHelper.published_push_key
      ].include?(item_key)
    end
  end
end
