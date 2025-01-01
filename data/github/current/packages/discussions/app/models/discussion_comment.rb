# typed: true
# frozen_string_literal: true

class DiscussionComment < ApplicationRecord::Domain::Discussions
  extend T::Sig

  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include UserContentEditable
  include Reaction::Subject::RepositoryContext
  include Spam::Spammable
  include InteractionBanValidation
  include Referrer
  include AbuseReportable
  include OrgBlockable
  include NotificationsContent::WithCallbacks
  include DiscussionComment::NewsiesAdapter
  include DiscussionComment::SearchAdapter
  include GitHub::MinimizeComment
  include Instrumentation::Model
  include EmailReceivable
  include Votable
  include AuthorAssociable
  include Reactable
  include ActionView::Helpers::TextHelper
  include Storage::UserAssetTransfer::SavedReplyCopyDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::DiscussionComment

  DOM_ID_PREFIX = GitHub::HTML::IssueMentionFilter::DISCUSSION_COMMENT_DOM_ID_PREFIX
  URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/discussions/{number}##{DOM_ID_PREFIX}{comment_id}").freeze
  FALLBACK_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/discussions").freeze

  # Public: Map the reason Symbols returned by #disallow_marking_as_answer_reason and
  # #disallow_unmarking_as_answer_reason to human-friendly phrases indicating why these operations may not proceed.
  DISALLOW_REASONS = {
    discussion_deleting: "belongs to a discussion that is being deleted",
    unsupported_category: "does not belong to a discussion in a category that supports answers",
    already_marked: "is already marked as the answer",
    already_unmarked: "is not currently marked as the answer",
    already_answered: "belongs to a discussion that is already answered",
    wiped: "may not be chosen as an answer because its contents have been wiped",
    minimized: "may not be chosen as an answer because it has been minimized",
    child_comment: "is not a top-level comment",
  }.freeze

  attribute :body, StringFromBinary.new

  sig { returns T::Boolean }
  def created_via_email?
    created_via_email
  end

  belongs_to :discussion, required: true, inverse_of: :comments
  belongs_to :user
  belongs_to :repository, required: true
  belongs_to :parent_comment, class_name: "DiscussionComment", counter_cache: :nested_comments_count
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration, foreign_key: :performed_by_integration_id, class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  setup_spammable(:user)
  setup_attachments
  setup_referrer

  # Internal: overrides the Referrer to be the discussion.
  sig { returns Referrer }
  def referrer
    discussion || self
  end

  has_many :reactions, class_name: "DiscussionCommentReaction"
  destroy_dependents_in_background :reactions

  has_many :comments, class_name: "DiscussionComment", foreign_key: :parent_comment_id # rubocop:todo Rails/InverseOf

  has_many :votes, class_name: "DiscussionCommentVote", foreign_key: "comment_id" # rubocop:todo Rails/InverseOf
  destroy_dependents_in_background :votes

  # rubocop:todo Rails/InverseOf
  has_many :upvotes, -> { where("discussion_comment_votes.upvote = 1") },
    class_name: "DiscussionCommentVote",
    foreign_key: "comment_id"
  has_many :downvotes, -> { where("discussion_comment_votes.upvote = 0") },
    class_name: "DiscussionCommentVote",
    foreign_key: "comment_id"
  # rubocop:enable Rails/InverseOf

  before_validation :set_repository, on: :create

  # Used to temporarily hold the current user, for use in creating events
  attr_accessor :actor
  attr_accessor :skip_user_blocking_validation
  attr_accessor :skip_update_discussion_comment_count
  alias :skip_update_discussion_comment_count? :skip_update_discussion_comment_count
  attr_accessor :was_answer

  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true,
    allow_nil: false, allow_blank: true
  validates :body, presence: true, on: :create
  validates :body, presence: true, on: :update, unless: :wiped?
  validate :user_exists_for_open_discussion, on: :create
  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :user_has_verified_email, on: :create
  validate :ensure_author_is_not_blocked, unless: :skip_user_blocking_validation?
  validate :ensure_parent_comment_is_for_discussion
  validate :ensure_at_most_one_level_deep
  validate :parent_comment_exists
  validate :parent_comment_is_not_hidden, on: :create
  validate :parent_comment_is_not_self, on: :update

  before_destroy :unmark_answer_on_deletion
  before_destroy :delete_associated_events
  after_destroy_commit :delete_wiped_parent_if_no_children

  # Hydro telemetry and audit logs
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  before_destroy :generate_webhook_payload_for_deletion
  after_destroy_commit :instrument_deletion_event
  after_destroy_commit :instrument_later_unmark_as_answer

  # Update discussion
  after_commit :update_discussion_comment_count, on: :create, unless: :skip_update_discussion_comment_count?
  after_destroy :update_discussion_comment_count
  after_destroy :update_parent_comment_websocket

  after_save_commit :detect_comment_language, if: :body_changed_after_commit?, unless: -> { GitHub.enterprise? }

  # Live updates
  after_commit(
    :notify_socket_subscribers,
    on: :update,
    if: -> do
      T.bind(self, DiscussionComment)
      body_changed_after_commit? || previous_changes.key?(:detected_language)
    end
  )
  after_commit :notify_socket_subscribers_on_create, on: :create
  after_commit :notify_discussion_summary_socket_subscribers, on: :update, if: :body_changed_after_commit?


  # Notifications
  after_commit :subscribe_and_notify, on: :create
  after_commit :update_subscriptions_and_notify, on: :update

  # Search
  after_commit :synchronize_search_index, on: :update, if: :body_changed_after_commit?

  # audit log for updates
  after_commit :audit_log_update_event, on: :update, if: :body_changed_after_commit?

  after_commit :create_initial_upvote, on: :create

  # Community Insights data
  after_commit :count_daily_contributors, on: [:create, :destroy]

  delegate :number, to: :discussion

  scope :for_user, ->(user) { where(user_id: user) }
  scope :for_discussion, ->(discussion) { where(discussion_id: discussion) }
  scope :after_comment, ->(comment) { where("discussion_comments.id > ?", comment) }
  scope :for_repository, ->(repo) { where(repository_id: repo) }
  scope :child_of, ->(comment) { where(parent_comment_id: comment) }
  scope :top_level, -> { where(parent_comment_id: nil) }
  scope :not_wiped, -> { where(deleted: false) }
  scope :not_minimized, -> { where(comment_hidden: false) }
  scope :created_after, -> (time) { where("discussion_comments.created_at > ?", time) }

  scope :chosen_answers, -> do
    joins("INNER JOIN discussions ON " \
          "discussion_comments.discussion_id = discussions.id AND " \
          "discussion_comments.id = discussions.chosen_comment_id")
  end

  scope :sorted_by, -> (order_str, direction) {
    field = order_str.to_s.downcase =~ /updated/ ? :updated_at : :created_at
    direction = direction.to_s.downcase == "asc" ? :asc : :desc
    order(field => direction)
  }

  enum :comment_hidden_by, GitHub::MinimizeComment::ROLES

  DEFAULT_MAX_RESULTS = 100

  # Override Reactable.reactions_by_reactable_ids to use discussion comment
  # reactions table
  sig { params(ids: T.untyped).returns(T.untyped) }
  def self.reactions_by_reactable_ids(ids)
    DiscussionCommentReaction.
      where(discussion_comment_id: ids).
      select(:discussion_comment_id, :content, :user_id).
      group_by(&:discussion_comment_id)
  end

  sig { params(viewer: T.untyped, anchor_id: T.untyped, older: T.untyped, newer: T.untyped).returns(T.untyped) }
  def reply_thread(viewer:, anchor_id:, older: 0, newer: 0)
    DiscussionComment::ReplyThread.for_parent_comment(
      self, viewer: viewer, anchor_id: anchor_id, older: older, newer: newer)
  end

  # Public: Is this comment in a public repository?
  sig { returns(T.untyped) }
  def public?
    discussion&.public?
  end

  sig { returns(T.untyped) }
  def repository_owner_login
    repository&.owner_login
  end

  sig { returns(String) }
  def author_display_login
    author.display_login
  end

  # Public: Deletes this comment if possible or wipes its contents and author if it cannot be deleted.
  #
  # actor - the currently authenticated User
  #
  # Returns a Boolean indicating success.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def wipe_or_destroy(actor)
    self.actor = actor

    if comments.exists?
      wipe
    else
      destroy
    end
  end

  # Public: Has this comment been wiped? Wiping a comment is what we do when it's a parent to
  # other comments and the user wants to delete it, so we can avoid deleting the record and
  # leaving the child comments orphaned.
  #
  # Returns a Boolean.
  sig { returns(T.untyped) }
  def wiped?
    deleted_at.present?
  end

  sig { returns(T.untyped) }
  def repository_name
    repository&.name
  end

  sig { returns(T.untyped) }
  def discussion_number
    discussion&.number
  end

  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.last_reported_at_by_comment_id(discussion, actor:, comments: nil)
    result = {}

    # Only staff can see abuse reports on discussion comments
    return result unless actor.site_admin?

    comments ||= discussion.filter_spam_comments_for(actor)
    promises = comments.map(&:async_last_reported_at)
    last_report_times = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = last_report_times[i]
    end

    result
  end

  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.top_report_reason_by_comment_id(discussion, actor:, comments: nil)
    result = {}

    # Only staff can see abuse reports on discussion comments
    return result unless actor.site_admin?

    comments ||= discussion.filter_spam_comments_for(actor)
    promises = comments.map(&:async_top_report_reason)
    top_reasons = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = top_reasons[i]
    end

    result
  end

  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.report_count_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(0)

    # Only staff can see abuse reports on discussion comments
    return result unless actor.site_admin?

    comments ||= discussion.filter_spam_comments_for(actor)
    promises = comments.map(&:async_report_count)
    report_counts = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = report_counts[i]
    end

    result
  end

  # Public: Get the latest user content edit for each comment in a discussion.
  #
  # discussion - a Discussion
  # actor - the current User
  #
  # Returns a Hash of DiscussionComment ID => UserContentEdit.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.latest_edit_by_comment_id(discussion, actor:, comments: nil)
    result = {}
    comments ||= discussion.filter_spam_comments_for(actor)
    promises = comments.map(&:async_latest_user_content_edit)
    latest_edits = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = latest_edits[i]
    end

    result
  end

  sig { returns(T.untyped) }
  def author
    user || User.ghost
  end

  sig { returns(T.untyped) }
  def authored_by_ghost?
    author.ghost?
  end

  # Public: Returns the ID of this comment.
  sig { returns(T.untyped) }
  def discussion_comment_id
    id
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_readable_by?(actor)
    async_discussion.then do |discussion|
      next Promise.resolve(false) unless discussion
      discussion.async_readable_by?(actor)
    end
  end

  # Public: Returns an existing DiscussionCommentVote from the given User for this DiscussionComment.
  sig { params(user: T.untyped, upvote: T.untyped).returns(T.untyped) }
  def vote_by(user, upvote:)
    votes
      .where(upvote: upvote)
      .for_user(user)
      .for_discussion(discussion_id)
      .first
  end

  # Public: Creates a DiscussionCommentVote for the given User for this DiscussionComment, if one
  # does not already exist. Returns true on success, or if the User has already voted on
  # this DiscussionComment, and false on failure.
  sig { params(user: T.untyped, upvote: T.untyped).returns(T.untyped) }
  def create_vote_for(user, upvote:)
    vote = DiscussionCommentVote.retry_on_find_or_create_error do
      votes.for_user(user).first ||
      DiscussionCommentVote.new(user: user, comment: self, discussion: discussion)
    end
    vote.upvote = upvote
    vote.save
    vote
  end

  sig { params(user: T.untyped).returns(T.untyped) }
  def upvote(user)
    create_vote_for(user, upvote: true).tap do |vote|
      notify_socket_subscribers if vote.persisted?
    end
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Determine which comments for the specified discussion have authors who can be
  # blocked by the given user. Should be kept in sync with OrgBlockable#async_viewer_can_block_from_org?.
  #
  # discussion - Discussion
  # actor - the current User
  # comments - optional list of DiscussionComments to use
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.blockable_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(false)

    return result unless actor
    return result unless discussion.in_organization?

    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_viewer_can_block_from_org?(actor)
    end

    blockable_statuses = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = blockable_statuses[i]
    end

    result
  end

  # Public: Determine which comments for the specified discussion have authors who can be
  # unblocked by the given user. Should be kept in sync with OrgBlockable#async_viewer_can_unblock_from_org?.
  #
  # discussion - Discussion
  # actor - the current User
  # comments - optional list of DiscussionComments to use
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.unblockable_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(false)

    return result unless actor
    return result unless discussion.in_organization?

    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_viewer_can_unblock_from_org?(actor)
    end

    unblockable_statuses = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = unblockable_statuses[i]
    end

    result
  end

  # Public: Determine which comments for the specified discussion can be reported by the
  # given user to a repository maintainer. Should be kept in sync with
  # AbuseReportable#async_viewer_can_report_to_maintainer?.
  #
  # discussion - Discussion
  # actor - the current User
  # comments - optional list of DiscussionComments to use
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.reportable_to_maintainer_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(false)

    return result unless GitHub.can_report?
    return result unless actor
    return result unless discussion.in_organization?

    repo = discussion.repository
    return result if repo.private?

    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_viewer_can_report_to_maintainer?(actor)
    end

    reportable_statuses = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = reportable_statuses[i]
    end

    result
  end

  # Public: Determine which comments for the specified discussion can be reported by the
  # given user. Should be kept in sync with AbuseReportable#async_viewer_can_report?.
  #
  # discussion - Discussion
  # actor - the current User
  # comments - optional list of DiscussionComments to use
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.reportable_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(false)

    return result unless GitHub.can_report?
    return result unless actor

    repo = discussion.repository
    return result if repo.private?

    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_viewer_can_report?(actor)
    end

    reportable_statuses = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = reportable_statuses[i]
    end

    result
  end

  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def async_reactable_by?(actor, interaction_allowed: nil)
    DiscussionCommentReaction.async_viewer_can_react?(actor, self, interaction_allowed: interaction_allowed)
  end

  alias_method :async_viewer_can_react?, :async_reactable_by?

  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def reactable_by?(actor, interaction_allowed: nil)
    async_reactable_by?(actor, interaction_allowed: interaction_allowed).sync
  end

  # Public: Determine which comments can be reported by the given user.
  #
  # discussion - Discussion whose comments are being checked
  # actor - the current User
  # comments - optional list of DiscussionComments to use
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.can_react_by_comment_id(discussion, actor:, comments: nil)
    result = Hash.new(false)
    return result unless actor
    return result if actor.should_verify_email?
    return result if actor.blocked_by?(discussion.user, discussion.repository_owner)

    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_reactable_by?(actor)
    end

    can_react_results = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = can_react_results[i]
    end

    result
  end

  # Public: Can the given actor delete the comment?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def deletable_by?(actor)
    return false unless actor
    response = ::Permissions::Enforcer.authorize(
      action: :delete_discussion_comment,
      actor: actor,
      subject: self
    )
    response.allow?
  end

  # Public: Can the given actor delete the comment?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_deletable_by?(actor)
    return false unless actor

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :delete_discussion_comment,
      actor: actor,
      subject: self
    ).then { |decision| decision.allow? }
  end

  sig { params(discussion: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.async_can_toggle_minimized_discussion_comment?(discussion, actor:)
    discussion.async_repository.then do |repo|
      repo.async_owner.then do |_owner|
        response = ::Permissions::Enforcer.authorize(
          action: :toggle_discussion_comment_minimize,
          actor: actor,
          subject: discussion,
        )

        response.allow?
      end
    end
  end

  # Public: Can the given actor see the hide/unhide buttons on a discussion comment in the given discussion?
  sig { params(discussion: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.can_toggle_minimized_discussion_comment?(discussion, actor:)
    async_can_toggle_minimized_discussion_comment?(discussion, actor: actor).sync
  end

  # Public: Can the given actor hide the comment?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_minimizable_by?(actor)
    # Site admins can always minimize comments via stafftools.
    return Promise.resolve(true) if actor.site_admin?

    async_discussion.then do |disc|
      DiscussionComment.can_toggle_minimized_discussion_comment?(disc, actor: actor)
    end
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_unminimizable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(true) if actor.site_admin?

    async_repository.then do |repo|
      next false unless repo

      repo.async_pushable_by?(actor).then do |is_pushable|
        next is_pushable if minimized_by_maintainer?
        next false unless minimized_by_author?

        is_pushable || actor.id == user_id
      end
    end
  end

  # Public: Was the comment body changed in previous_changes? We use this to determine
  # if body changes _only_ after_commit.
  sig { returns(T.untyped) }
  def body_changed_after_commit?
    previous_changes.key?(:body)
  end

  sig { returns(T.untyped) }
  def notify_socket_subscribers
    channel = GitHub::WebSocket::Channels.discussion(discussion)

    GitHub::WebSocket.notify_discussion_channel(discussion, channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "discussion comment ##{id} updated",
      gid: global_relay_id,
    )
  end

  sig { returns(T.untyped) }
  def notify_discussion_summary_socket_subscribers
    channel = GitHub::WebSocket::Channels.discussion_summary(discussion)

    GitHub::WebSocket.notify_discussion_channel(discussion, channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "discussion comment ##{id} updated",
      gid: global_relay_id,
    )
  end

  sig { returns(T.untyped) }
  def notify_socket_subscribers_on_create
    # If it's a top-level comment, trigger an update for the timeline.
    # If this is a nested comment, trigger an update for the parent comment.

    if top_level_comment?
      channel = GitHub::WebSocket::Channels.discussion_timeline(discussion)
      return unless channel

      GitHub::WebSocket.notify_discussion_channel(
        discussion,
        channel,
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "discussion comment ##{id} updated",
      )
    else
      channel = GitHub::WebSocket::Channels.discussion(discussion)
      return unless channel

      GitHub::WebSocket.notify_discussion_channel(discussion, channel,
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "discussion comment ##{id} updated",
        gid: parent_comment&.global_relay_id,
      )
    end
  end

  sig { returns Promise[String] }
  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then(&:async_owner).then do
      async_discussion.then do |discussion|
        discussion_number = if discussion
          discussion.number
        elsif deleted_discussion = DeletedDiscussion.find_by(old_discussion_id: discussion_id)
          deleted_discussion.number
        end

        if discussion_number.nil?
          next FALLBACK_URI_TEMPLATE.expand(owner: repository&.owner_display_login, name: repository&.name)
        end

        URI_TEMPLATE.expand(
          owner:  repository&.owner_display_login,
          name:   repository&.name,
          number: discussion_number,
          comment_id: id,
        )
      end
    end
  end

  # Public: Is this comment a reply to the original discussion and not another comment?
  sig { returns T::Boolean }
  def top_level_comment?
    parent_comment_id.nil?
  end

  # Public: Is this comment a nested (or child) comment, meaning is it a reply to
  # another comment on the Discussion and not to the original Discussion itself?
  sig { returns T::Boolean }
  def nested?
    !top_level_comment?
  end

  # Public: Can a comment be made in reply to this comment, nested under it?
  sig { returns T::Boolean }
  def can_be_commented_on?
    top_level_comment? && !comment_hidden
  end

  # Public: How many comments are nested under this comment?
  sig { returns Integer }
  def comment_count
    nested_comments_count
  end

  # Public: Can the given actor change the contents of this comment? Should be kept in sync
  # with #modifiable_by_comment_id.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def modifiable_by?(actor)
    return false unless actor
    return false unless User::InteractionAbility.interaction_allowed?(user: actor, repository: repository)

    response = ::Permissions::Enforcer.authorize(
      action: :edit_discussion_comment,
      actor: actor,
      subject: self
    )
    response.allow?
  end

  sig { params(actor: T.untyped, skip_interaction_check: T.untyped).returns(T.untyped) }
  def async_modifiable_by?(actor, skip_interaction_check: false)
    async_repository.then do |repository|
      next Promise.resolve(false) unless actor

      # Interaction check, if requested
      interaction_allowed_promise =
        if skip_interaction_check
          Promise.resolve(true)
        else
          User::InteractionAbility.async_interaction_allowed?(user: actor, repository: repository)
        end

      interaction_allowed_promise.then do |interaction_allowed|
        next Promise.resolve(false) unless interaction_allowed

        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :edit_discussion_comment,
          actor: actor,
          subject: self
        ).then { |decision| decision.allow? }
      end
    end
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_viewer_can_update?(viewer)
    async_repository.then do |repository|
      repository && viewer_cannot_update_reasons(viewer).empty?
    end
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def viewer_can_update?(viewer)
    async_viewer_can_update?(viewer).sync
  end

  # Public: Determine if the specified user can mark and unmark the correct answer in the
  # given discussion.
  #
  # discussion - a Discussion
  # actor - the currently authenticated User
  #
  # Returns a Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.can_toggle_answer_in_discussion?(discussion, actor:)
    async_can_toggle_answer_in_discussion?(discussion, actor: actor).sync
  end

  # Public: Async version of .can_toggle_answer_in_discussion?.
  sig { params(discussion: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.async_can_toggle_answer_in_discussion?(discussion, actor:)
    discussion.async_repository.then do |repository|
      # Ensure the feature flag is enabled and discussions are turned "on"
      next false unless repository&.discussions_active?

      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :toggle_discussion_answer,
        actor: actor,
        subject: discussion
      ).then(&:allow?)
    end
  end

  # Public: Report a reason that this comment is not eligible to be chosen as an answer to its discussion.
  #
  # Returns a Symbol from DISALLOW_REASONS describing the reason if one applies, or nil if this comment is eligible.
  sig { returns T.nilable(Symbol) }
  def disallow_marking_as_answer_reason
    async_disallow_marking_as_answer_reason.sync
  end

  # Public: Async flavor of #disallow_marking_as_answer_reason.
  #
  # Returns a Promise that resolves to a Symbol or nil.
  sig { returns Promise[T.nilable(Symbol)] }
  def async_disallow_marking_as_answer_reason
    async_discussion.then do |discussion|
      next :discussion_deleting unless discussion

      discussion.async_supports_mark_as_answer?.then do |supported|
        next :unsupported_category unless supported

        if discussion.answered?
          if answer?
            next :already_marked
          else
            next :already_answered
          end
        end

        next :wiped if wiped?
        next :minimized if minimized?

        nil
      end
    end
  end

  # Public: Is this comment one that is eligible to be marked as the answer?
  sig { returns T::Boolean }
  def marking_as_answer_allowed?
    disallow_marking_as_answer_reason.nil?
  end

  # Public: Can this user mark this comment as the answer to its discussion? Accounts for authzd permissions, discussion
  # category configuration, and other model state like if the discussion already has a different answer marked.
  #
  # Returns a boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_mark_as_answer?(actor)
    async_can_mark_as_answer?(actor).sync
  end

  # Public: Async flavor of #can_mark_as_answer?.
  #
  # Returns a Promise that resolves to a boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_mark_as_answer?(actor)
    async_disallow_marking_as_answer_reason.then do |disallow_reason|
      next false if disallow_reason.present?

      self.class.async_can_toggle_answer_in_discussion?(discussion, actor: actor)
    end
  end

  # Public: Determine which comment can be unmarked as the answer for a given discussion.
  #
  # discussion - a Discussion
  # actor - the current User or nil
  #
  # Returns a Hash of DiscussionComment ID => Boolean.
  sig { params(discussion: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.can_unmark_as_answer_by_comment_id(discussion, actor:)
    result = Hash.new(false)

    return result unless can_toggle_answer_in_discussion?(discussion, actor: actor)

    if discussion.chosen_comment_id
      result[discussion.chosen_comment_id] = true
    end

    result
  end

  # Public: Report a reason that this comment is not eligible to be removed as the chosen answer within its discussion.
  #
  # Returns a Symbol chosen from DISALLOW_REASONS describing the reason if one applies, or nil if this comment is
  # eligible to unmark.
  sig { returns T.nilable(Symbol) }
  def disallow_unmarking_as_answer_reason
    async_disallow_unmarking_as_answer_reason.sync
  end

  # Public: Async version of #disallow_unmarking_as_answer_reason.
  #
  # Returns a Promise that resolves to a Symbol or nil.
  sig { returns Promise[T.nilable(Symbol)] }
  def async_disallow_unmarking_as_answer_reason
    async_discussion.then do |discussion|
      next :discussion_deleting unless discussion

      discussion.async_supports_mark_as_answer?.then do |supported|
        next :unsupported_category unless supported

        async_answer?.then do |answer|
          next :already_unmarked unless answer

          nil
        end
      end
    end
  end

  # Public: Is this comment eligible to be unmarked as the answer?
  sig { returns T::Boolean }
  def unmarking_as_answer_allowed?
    disallow_unmarking_as_answer_reason.nil?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_unmark_as_answer?(actor)
    async_can_unmark_as_answer?(actor).sync
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_unmark_as_answer?(actor)
    async_discussion.then do |discussion|
      Promise.all([
        async_disallow_unmarking_as_answer_reason,
        self.class.async_can_toggle_answer_in_discussion?(discussion, actor: actor)
      ]).then { |disallow_reason, authorized| disallow_reason.nil? && authorized }
    end
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_viewer_cannot_update_reasons(viewer)
    Promise.resolve(viewer_cannot_update_reasons(viewer))
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def viewer_cannot_update_reasons(viewer)
    return [:login_required] unless viewer
    context = { repo: repository, discussion: discussion }
    errors = ContentAuthorizer.authorize(viewer, :DiscussionComment, :edit, context).errors.
      map(&:symbolic_error_code)
    errors << :insufficient_access unless modifiable_by?(viewer)
    errors
  end

  sig { returns T::Boolean }
  def answer?
    async_answer?.sync
  end

  sig { returns Promise[T::Boolean] }
  def async_answer?
    return Promise.resolve(T.let(false, T::Boolean)) unless persisted?

    async_discussion.then do |discussion|
      next false unless discussion && id == discussion.chosen_comment_id

      discussion.async_supports_mark_as_answer?
    end
  end

  sig { params(actor: T.untyped, performed_via_integration: T.untyped).returns(T.untyped) }
  def mark_as_answer(actor: self.actor, performed_via_integration: nil)
    discussion = self.discussion
    return false unless discussion

    discussion.chosen_comment_id = id
    return false unless discussion.save

    event = DiscussionEvent.new(discussion: discussion, actor: actor,
      event_type: :answer_marked, comment: self, performed_via_integration: performed_via_integration)
    return false unless event.save

    GlobalInstrumenter.instrument "discussions_comment_marked_as_answer", {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion.id,
      discussion_comment_id: id,
      discussion_comment: self,
      actor_id: actor&.id,
      actor: actor,
      action: :MARKED_AS_ANSWER,
      action_timestamp: Time.now
    }

    GlobalInstrumenter.instrument "discussion_comment.mark_as_answer", discussion_comment: self,
      actor: actor

    GitHub.instrument "discussion.answer", discussion: discussion, action: :answered, answer_id: id, actor: actor

    true
  end

  sig { returns(T.untyped) }
  def unmark_answer_on_deletion
    unmark_as_answer(on_deletion: true)
  end

  sig { returns(T.untyped) }
  def delete_associated_events
    DiscussionEvent.for_comment(id).destroy_all
  end

  sig { params(actor: T.untyped, performed_via_integration: T.untyped, on_deletion: T.untyped).returns(T.untyped) }
  def unmark_as_answer(actor: self.actor, performed_via_integration: nil, on_deletion: false)
    discussion = self.discussion
    return false unless discussion
    return false unless discussion.chosen_comment_id == id

    discussion.chosen_comment_id = nil
    return false unless discussion.save
    self.actor = actor

    unless on_deletion
      event = DiscussionEvent.new(discussion: discussion, actor: actor,
        event_type: :answer_unmarked, comment: self, performed_via_integration: performed_via_integration)
      return false unless event.save
    end

    self.was_answer = true

    GlobalInstrumenter.instrument "discussions_comment_marked_as_answer", {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion.id,
      discussion_comment_id: id,
      discussion_comment: self,
      actor_id: actor&.id,
      actor: actor,
      action: :UNMARKED_AS_ANSWER,
      action_timestamp: Time.now
    }


    GlobalInstrumenter.instrument "discussion_comment.unmark_as_answer", discussion_comment: self,
      actor: actor

    # if we're here because the comment is being deleted, we need to get the comment data into a webhook payload now,
    # but defer the instrumentation until after_destroy_commit
    if on_deletion
      generate_webhook_payload_for_unmark_answer
    else
      GitHub.instrument "discussion.unanswer", discussion: discussion, action: :unanswered, answer_id: id, actor: actor
    end

    true
  end

  sig { returns(T.untyped) }
  def generate_webhook_payload_for_unmark_answer
    if !actor || actor&.spammy? || wiped?
      @delivery_system_for_unanswer = nil
      return
    end

    event_for_unanswer = Hook::Event::DiscussionEvent.new(
      action: :unanswered,
      answer_id: id,
      actor_id: actor&.id,
      triggered_at: Time.now,
      discussion_id: discussion,
    )
    @delivery_system_for_unanswer = Hook::DeliverySystem.new(event_for_unanswer)
    @delivery_system_for_unanswer.generate_hookshot_payloads
  end

  sig { returns(T.untyped) }
  def instrument_later_unmark_as_answer
    return unless was_answer
    unless defined?(@delivery_system_for_unanswer)
      raise "`generate_webhook_payload_for_unmark_answer` must be called before `instrument_later_unmark_as_answer`"
    end

    @delivery_system_for_unanswer&.deliver_later
  end

  sig { returns(T.untyped) }
  def delete_wiped_parent_if_no_children
    parent_comment = self.parent_comment
    return unless parent_comment&.wiped?
    parent_comment.destroy unless parent_comment.comments.exists?
  end

  # Public: Remove the given discussion comments as the chosen answer in their discussions.
  #
  # chosen_comments - a list of DiscussionComments that are marked as the answer
  sig { params(chosen_comments: T.untyped).returns(T.untyped) }
  def self.unmark_as_answers(chosen_comments)
    discussion_ids = chosen_comments.map(&:discussion_id).compact.uniq
    discussions = Discussion.where(id: discussion_ids)
    discussions.each do |discussion|
      discussion.events.create(event_type: :answer_unmarked, comment_id: discussion.chosen_comment_id)
      GitHub.instrument "discussion.unanswer", discussion: discussion, action: :unanswered, answer_id: discussion.chosen_comment_id, actor: User.ghost
    end
    discussions.update_all(chosen_comment_id: nil)
  end

  # Public: Determine if this comment is locked for the given user.
  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_locked_for?(viewer)
    async_discussion.then do |discussion|
      discussion.async_locked_for?(viewer)
    end
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_reactions_locked_for?(viewer)
    async_discussion.then do |discussion|
      discussion.async_reactions_locked_for?(viewer)
    end
  end

  sig { returns(T.untyped) }
  def reaction_groups
    async_reaction_groups.sync
  end

  sig { returns(T.untyped) }
  def async_reaction_groups
    Platform::Loaders::DiscussionCommentReactionGroups.load(self)
  end

  # Public: Returns the list of reactions groups of each discussion comment
  #
  # discussion - a Discussion
  # actor - the current User or nil
  # comments - the list of comments to use
  #
  # Returns a Hash of DiscussionComment ID => Array of ReactionGroup.
  sig { params(discussion: T.untyped, actor: T.untyped, comments: T.untyped).returns(T.untyped) }
  def self.reaction_groups_by_comment_id(discussion, actor:, comments: nil)
    result = {}
    comments ||= discussion.filter_spam_comments_for(actor)

    promises = comments.map do |comment|
      comment.async_reaction_groups
    end

    reaction_groups = Promise.all(promises).sync

    comments.each_with_index do |comment, i|
      result[comment.id] = reaction_groups[i]
    end

    result
  end

  # Public: Checks spamminess of associated discussion.
  #
  # Returns a Boolean.
  sig { returns(T.untyped) }
  def belongs_to_spammy_content?
    discussion&.spammy?
  end

  sig { params(actor: T.untyped, content: T.untyped).returns(T.untyped) }
  def react(actor:, content:)
    DiscussionCommentReaction.react(user: actor, discussion_comment_id: id, content: content)
  end

  sig { returns(T.untyped) }
  def threaded?
    parent_comment_id.present?
  end

  sig { params(actor: T.untyped, content: T.untyped).returns(T.untyped) }
  def unreact(actor:, content:)
    DiscussionCommentReaction.unreact(user: actor, discussion_comment_id: id, content: content)
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  sig { returns(T.untyped) }
  def safe_user
    user || User.ghost
  end

  sig { returns(T.untyped) }
  def detect_comment_language
    DetectCommentLanguageJob.enqueue_once_per_interval(
      args: [id, self.class.name],
      unique_id: [self.class.name, id, latest_user_content_edit&.id].compact.join(":"),
      interval: 10.minutes,
      run_at_beginning_of_interval: true
    )
  end

  # Public: A human-friendly reason this comment was memoized. Does not actually confirm if the comment is memoized,
  # so you'll want to check that before relying on the return value here.
  #
  # viewer - the currently authenticated User or nil
  #
  # Returns a String.
  sig { params(viewer: T.untyped).returns(T.untyped) }
  def minimization_reason_for(viewer:)
    minimized_reason = comment_hidden_classifier&.downcase

    if minimized_reason == "spam" && viewer && spammy? && user&.spammy? && viewer.site_admin?
      return "This comment and user were marked as spammy."
    end

    case minimized_reason
    when "spam"
      "This comment was marked as spam."
    when "abuse"
      if minimized_by_staff?
        url = ActionController::Base.helpers.link_to("GitHub Acceptable Use Policies", "https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies")
        safe_join(["This comment was marked as a violation of ", url])
      else
        "This comment was marked as disruptive content."
      end
    when "off-topic"
      "This comment was marked as off-topic."
    when "outdated"
      "This comment has been hidden."
    when "resolved"
      "This comment has been hidden."
    else
      "This comment has been minimized."
    end
  end

  sig { params(comment_id: T.any(String, Integer)).returns(String) }
  def self.dom_id(comment_id)
    "#{DOM_ID_PREFIX}#{comment_id}"
  end

  sig { returns(T.nilable(String)) }
  def dom_id
    id = self.id
    self.class.dom_id(id) if id
  end

  sig { returns(T.untyped) }
  def permalink_id
    return unless persisted?
    "#{dom_id}-permalink"
  end

  private

  # Private: Wipes the body of this comment and sets its deleted_at to
  # the current time, thus soft-deleting it, as well as unmarking it as
  # the answer if it's currently the answer.
  #
  # Returns a Boolean indicating success.
  sig { returns T.nilable(T::Boolean) }
  def wipe
    generate_webhook_payload_for_deletion
    new_attrs = { body: "", deleted_at: Time.zone.now }
    success = if answer?
      transaction do
        success = T.let(unmark_as_answer(on_deletion: true) && update(new_attrs), T::Boolean)
        raise ActiveRecord::Rollback unless success
        success
      end
    else
      update(new_attrs)
    end
    instrument_deletion_event if success
    instrument_later_unmark_as_answer if success
    success
  end

  sig { void }
  def user_exists_for_open_discussion
    if user.nil? && discussion&.open?
      errors.add(:user, "can't be blank")
    end
  end

  sig { void }
  def user_has_verified_email
    user = self.user
    return unless user

    # If we're converting an existing issue to a discussion, don't require the issue comment
    # to have been created by a user with a verified email address.
    discussion = self.discussion
    return unless discussion && discussion.open?

    # The Bot user associated with a GitHub App never has a verified email.
    return if user.bot?

    if user.should_verify_email?
      errors.add(:user, "must have a verified email address")
    end
  end

  sig { void }
  def update_discussion_comment_count
    discussion&.update_comment_count
  end

  sig { void }
  def set_repository
    discussion = self.discussion
    return unless discussion
    self.repository = discussion.repository
  end

  sig { void }
  def ensure_author_is_not_blocked
    discussion = self.discussion
    user = self.user
    return unless user && discussion
    return if discussion.repository&.pushable_by?(user)

    potential_blockers_to_check = [discussion.user]
    potential_blockers_to_check << repository&.owner if repository&.owner

    if user.blocked_by?(potential_blockers_to_check)
      errors.add(:user, "cannot comment at this time")
    end
  end

  sig { returns T::Boolean }
  def skip_user_blocking_validation?
    # Allow owners to minimize comments that blocked users authored
    # before they were blocked.
    # https://github.com/github/communities/issues/469
    skip_user_blocking_validation || comment_hidden_changed?
  end

  sig { void }
  def ensure_parent_comment_is_for_discussion
    parent_comment = self.parent_comment
    return unless parent_comment && discussion_id

    if parent_comment.discussion_id != discussion_id
      errors.add(:parent_comment, "is in a different discussion")
    end
  end

  sig { void }
  def ensure_at_most_one_level_deep
    parent_comment = self.parent_comment
    return unless parent_comment

    if parent_comment.parent_comment
      errors.add(:parent_comment, "is already in a thread, cannot reply to it")
    end
  end

  sig { void }
  def parent_comment_exists
    return unless parent_comment_id

    unless parent_comment
      errors.add(:parent_comment, "does not exist")
    end
  end

  sig { void }
  def parent_comment_is_not_hidden
    parent_comment = self.parent_comment
    return unless parent_comment

    if parent_comment.comment_hidden
      errors.add(:parent_comment, "has been hidden and cannot be replied to")
    end
  end

  sig { void }
  def parent_comment_is_not_self
    return unless parent_comment_id

    if parent_comment_id == id
      errors.add(:parent_comment, "cannot be itself")
    end
  end

  sig { void }
  def update_parent_comment_websocket
    parent_comment = self.parent_comment
    return unless discussion && parent_comment

    channel = GitHub::WebSocket::Channels.discussion(discussion)
    GitHub::WebSocket.notify_discussion_channel(discussion, channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "discussion comment ##{id} deleted",
      gid: parent_comment.global_relay_id,
    )
  end

  sig { void }
  def instrument_creation_event
    # Hydro
    GlobalInstrumenter.instrument "discussion_comment.create",
      discussion_comment: self, actor: user

    # Hydro v2
    message = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion_id,
      discussion: discussion,
      actor_id: user&.id,
      actor: user,
      discussion_comment_id: id,
      discussion_comment: self,
      action: :ACTION_COMMENT_CREATED,
      action_timestamp: Time.now
    }
    GlobalInstrumenter.instrument "discussions_comment", message

    # Webhooks
    instrument :create, action: :created, actor_id: user_id
  end

  sig { void }
  def instrument_update_event
    previous_body = previous_changes.dig(:body, 0)

    GlobalInstrumenter.instrument "discussion_comment.update", {
      discussion_comment: self,
      previous_body: previous_body,
      actor: actor || editor
    }

    # Hydro v2
    message = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion_id,
      discussion: discussion,
      actor_id: actor&.id,
      actor: actor || editor,
      discussion_comment_id: id,
      discussion_comment: self,
      action: :ACTION_COMMENT_UPDATED,
      action_timestamp: Time.now
    }
    GlobalInstrumenter.instrument "discussions_comment", message
  end

  # we need to generate the payload before the discussion comment is wiped or deleted, so we don't lose the data
  sig { void }
  def generate_webhook_payload_for_deletion
    if !actor || actor&.spammy? || wiped?
      @delivery_system_for_delete = nil
      return
    end

    event_for_delete = Hook::Event::DiscussionCommentEvent.new(
      action: :deleted,
      comment_id: id,
      actor_id: actor&.id,
      triggered_at: Time.now
    )
    @delivery_system_for_delete = Hook::DeliverySystem.new(event_for_delete)
    @delivery_system_for_delete.generate_hookshot_payloads
  end

  sig { void }
  def instrument_deletion_event
    unless defined?(@delivery_system_for_delete)
      raise "`generate_webhook_payload_for_deletion` must be called before `instrument_deletion_event`"
    end

    # Webhooks
    @delivery_system_for_delete&.deliver_later

    # Audit log
    instrument :destroy

    # Hydro
    GlobalInstrumenter.instrument "discussion_comment.delete",
      discussion_comment: self, actor: actor

    # Hydro v2
    message = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: actor&.id,
      actor: actor,
      discussion_comment_id: id,
      discussion_comment: self,
      action: :ACTION_COMMENT_DELETED,
      action_timestamp: Time.now
    }
    GlobalInstrumenter.instrument "discussions_comment", message
  end

  sig { void }
  def audit_log_update_event
    previous_body = previous_changes[:body].try(:first)

    instrument :update, action: :edited, old_body: previous_body, actor: actor, wiped: wiped?
  end

  sig { returns Symbol }
  def event_prefix() :discussion_comment end

  sig { returns T::Hash[Symbol, T.untyped] }
  def event_payload
    repository = self.repository
    payload = {
      :repo =>        repository,
      :discussion =>  discussion,
      event_prefix => self,
      :body =>        body,
      :user =>        user,
    }

    if repository&.organization
      payload[:org] = repository.organization
    end

    payload
  end

  sig { void }
  def create_initial_upvote
    return if nested?
    DiscussionCommentVote.create(discussion: discussion, comment: self, user: user, upvote: true)
  end

  sig { void }
  def count_daily_contributors
    created_at = self.created_at || Time.current
    CommunityInsights::DiscussionsDailyContributorsJob.perform_later(repository_id, created_at.to_date)
  end

  sig { override.returns(T.nilable(Repository)) }
  def saved_reply_copy_target
    self.repository
  end
end
