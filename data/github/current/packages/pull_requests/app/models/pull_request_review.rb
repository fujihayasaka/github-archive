# typed: true
# frozen_string_literal: true

class PullRequestReview < ApplicationRecord::Domain::IssuesPullRequests
  extend T::Sig

  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::Relay::GlobalIdentification
  include GitHub::MinimizeComment
  include Spam::Spammable
  include Instrumentation::Model
  include EmailReceivable
  include Workflow
  include NotificationsContent::WithCallbacks
  include Reaction::Subject::RepositoryContext
  include UserContentEditable
  include InteractionBanValidation
  include AuthorAssociable
  include OrgBlockable
  include AbuseReportable
  include GitHub::RateLimitedCreation
  include LegacyImportable
  include Reactable
  include PreloadableAttributes
  include Referrer

  include Storage::UserAssetTransfer::SavedReplyCopyDependency

  BooleanPromise = T.type_alias { T.any(Promise[T::Boolean], Promise[TrueClass], Promise[FalseClass]) }

  # Used to bypass active record callbacks on create via the
  # CreateNewPullRequestReviewCommentOrchestration
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :skip_review_callbacks
  alias_method :skip_review_callbacks?, :skip_review_callbacks

  NEEDS_COMMENTS_WHEN_REQUESTING_CHANGES = "You need to leave a comment indicating the requested changes."

  SUBMISSION_EVENTS = [:comment, :approve, :request_changes]
  ALL_EVENTS = SUBMISSION_EVENTS + [:dismiss]
  MERGE_BASE_SHA_LENGTH = 40

  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :validate_body_is_editable, on: :update, if: :body_changed?
  validate :one_pending_review_per_user_and_pull_request, if: :pending?
  validate :validate_pull_request_lock, on: :create
  validate :ensure_creator_is_not_blocked, unless: :comment_hidden_changed?
  validate :explanation_exists?, if: :explanation_required?
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true
  validates :head_sha, presence: true
  validates :pull_request_id, presence: true
  validates :state, presence: true
  validates :user_id, presence: true
  validates :repository_id, presence: true, on: :create
  validates :merge_base_sha, length: { is: MERGE_BASE_SHA_LENGTH }, allow_nil: true
  validate :variant_type_supports_user

  attr_preloadable :async_author_can_push, :author_association_symbol

  # Certain reviews behave somewhat differently.
  enum :variant_type, { vanilla: 0, code_scanning: 1, copilot: 2, dependabot: 3 }

  workflow :state do
    state :pending, 0 do
      event :comment, transitions_to: :commented
      event :approve, transitions_to: :approved
      event :request_changes, transitions_to: :changes_requested
    end

    state :commented, 1 do
      on_entry do
        T.bind(self, PullRequestReview)
        after_submission
      end
    end

    state :changes_requested, 30 do
      on_entry do
        T.bind(self, PullRequestReview)
        after_submission
      end
      event :dismiss, transitions_to: :dismissed
    end

    state :approved, 40 do
      on_entry do
        T.bind(self, PullRequestReview)
        after_submission
      end
      event :dismiss, transitions_to: :dismissed
    end

    state :dismissed, 50 do
      on_entry do
        T.bind(self, PullRequestReview)
        after_dismissal
      end
    end

    on_transition do |from, to, _event, *event_args, **_kwargs|
      Rails.logger.debug { "on_transition from #{from} to #{to} with #{event_args}" }
    end
  end

  # NOTE: All after_* callback logic should go into the below methods.
  # It is much easier to follow the sequence of callback logic by keeping them
  # to a single method each, rather than having scattered callbacks all over.
  before_validation :set_repository_id
  before_save :set_previously_submitted_review_author_ids # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_create :after_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :after_commit, if: :call_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update_event, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_dismiss_event, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_subscriptions_and_notify, on: :update, if: :update_subscriptions_and_notify? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :call_auto_merge_job_enqueuer, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_pull_request_counters, unless: :skip_review_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :trigger_platform_subscriptions, unless: :skip_review_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :log_missing_merge_base_sha, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_destroy_commit :after_destroy_commit # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  belongs_to :pull_request, touch: true
  belongs_to :user

  has_many :review_comments, class_name: "PullRequestReviewComment", inverse_of: :pull_request_review
  destroy_dependents_in_background :review_comments, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :review_threads, class_name: "PullRequestReviewThread", inverse_of: :pull_request_review

  belongs_to :repository

  has_many :pull_request_reviews_review_requests
  destroy_dependents_in_background :pull_request_reviews_review_requests, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :review_requests, through: :pull_request_reviews_review_requests

  has_many :reactions, class_name: "PullRequestReviewReaction"
  def async_reactable_by?(viewer) = async_viewer_can_react?(viewer)

  # remove this once double-writing reactions gets removed. This is only here for destroy_dependents_in_background.
  has_many :legacy_reactions, class_name: "Reaction", as: :subject
  destroy_dependents_in_background :legacy_reactions

  # Virtual column ( body is not null or body > '')
  attr_readonly :has_body

  # Transient attribute used to determine if a new reviewer has been added
  # to a pull request when a row for this model is committed to the database.
  attr_accessor :previously_submitted_review_author_ids

  setup_attachments
  setup_spammable(:user)
  T.unsafe(self).setup_referrer

  scope :has_body, -> { where(has_body: true) }

  # Public: Return non-pending reviews
  scope :submitted, -> { where.not(state: state_value(:pending)) }

  # Public: Return pending reviews
  scope :pending, -> { where(state: state_value(:pending)) }

  # Limited to those on repositories in a given organization
  scope :for_organization, ->(organization) do
    repo_ids = Repository.where(organization_id: organization).pluck(:id)
    if repo_ids.empty?
      none
    else
      where(repository_id: repo_ids)
    end
  end

  # All visible, non-pending, reviews for the current viewer. Viewers can see
  # their own pending reviews.
  #
  # viewer - The User who is viewing the reviews (current_user)
  scope :for_viewer, -> (viewer) {
    if viewer
      where("`pull_request_reviews`.`user_id` = ? OR `pull_request_reviews`.`state` <> ?", viewer.id, PullRequestReview.state_value(:pending))
    else
      where("`pull_request_reviews`.`state` <> ?", PullRequestReview.state_value(:pending))
    end
  }

  scope :not_commented, -> { where.not(state: state_value(:commented)) }
  scope :body_present, -> { where.not(body: [nil, ""]) }
  scope :with_non_reply_comments, -> {
    where(review_comments: { reply_to_id: nil })
      .where.not(review_comments: { id: nil })
  }

  # All reviews that are visible to a viewer on the timeline.
  #
  # viewer - User who is viewing the timeline
  scope :visible_in_timeline_for, -> (viewer) do
    non_reply_comments_review_ids = self.joins(:review_comments).with_non_reply_comments.pluck(:pull_request_review_id)
    not_commented
      .or(body_present)
      .or(where(id: non_reply_comments_review_ids))
      .for_viewer(viewer)
      .filter_spam_for(viewer)
      .group(:id)
      .order("NULL") # Optimization: Avoid sorting when grouping
  end

  batch_method(:dismissed_review_state) do |reviews|
    dismissed_reviews = reviews.select(&:dismissed?)
    states = {}

    unless dismissed_reviews.empty?
      bindings = {
        pull_request_review_ids: dismissed_reviews.map(&:id),
        pull_request_ids: dismissed_reviews.map(&:pull_request_id),
      }

      # Selecting and then omitting issue_events.id to be compatible with vitess
      states = IssueEvent.connection.select_rows(Arel.sql(<<-SQL, **bindings)).map { |review_id, state_was, _| [review_id, state_was] }.to_h
        SELECT issue_event_details.pull_request_review_id, issue_event_details.pull_request_review_state_was, issue_events.id
        FROM pull_requests
        JOIN issues ON issues.pull_request_id = pull_requests.id
        JOIN issue_events ON issue_events.issue_id = issues.id
        JOIN issue_event_details ON issue_event_details.issue_event_id = issue_events.id
        WHERE pull_requests.id IN (:pull_request_ids)
        AND issue_events.event = 'review_dismissed'
        AND issue_event_details.pull_request_review_id IN (:pull_request_review_ids)
        AND issue_event_details.pull_request_review_state_was IS NOT NULL
        ORDER BY issue_events.id DESC
      SQL
    end

    reviews.index_with { |review| states[review.id] }
  end

  # This loads all of the review comment ids of the comments that will be
  # displayed on any review threads belonging to this review on the timeline.
  batch_method(:prelude_thread_comment_ids) do |reviews, viewer|
    comment_ids_by_review_id = ::PullRequestReviewComment.joins(:pull_request_review_thread).
      visible_to(viewer).
      where("pull_request_review_threads.pull_request_review_id": reviews.map(&:id)).
      pluck("pull_request_review_threads.pull_request_review_id", :id).
      each_with_object(Hash.new { |h, k| h[k] = [] }) { |(review_id, id), hash| hash[review_id] << id }
    reviews.index_with { |review| comment_ids_by_review_id[review.id] }
  end

  batch_method(:prelude_viewer_can_react) do |reviews, viewer|
    result = Promise.all(
      reviews.map { |review| review.async_viewer_can_react?(viewer) }
    ).sync
    reviews.zip(result).to_h
  end

  # Public: Return the most recent review for each user
  sig { params(pull_request: PullRequest).returns(T::Array[PullRequestReview]) }
  def self.recent_approved_per_user(pull_request)
    # Group-wise maximum against id column rather than updated_at because
    # http://bugs.mysql.com/bug.php?id=54784
    sql = <<-SQL
      SELECT r1.*
      FROM pull_request_reviews r1
      INNER JOIN
      (
        SELECT max(id) as id
        FROM pull_request_reviews
        WHERE pull_request_id = :pull_request_id
        AND   state = :state
        GROUP BY user_id
      ) r2
      ON r1.id = r2.id
      ORDER BY r1.updated_at desc
    SQL
    self.find_by_sql(Arel.sql(sql, state: state_value(:approved), pull_request_id: pull_request.id))
  end

  # Get the Integer value matching a certain state
  sig { params(name: T.any(String, Symbol)).returns(Integer) }
  def self.state_value(name)
    workflow_spec.states[name.to_sym].value
  end

  # Gets the name of the state from the integer value
  sig { params(int: T.nilable(Integer)).returns(T.nilable(Symbol)) }
  def self.state_name(int)
    result = workflow_spec.states.values.find { |state| state.value == int }
    result ? result.name : nil
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  sig { returns(User) }
  def safe_user
    user || User.ghost
  end

  # Internal: Determine if an event is valid to be called from the current state
  # for this pull request review.
  sig { params(event: T.any(Symbol, String)).returns(T::Boolean) }
  def can_trigger?(event)
    event = event.to_sym
    raise(ArgumentError.new("unknown event")) unless ALL_EVENTS.include?(event)
    method = "can_#{event}?"
    public_send(method)
  end

  # Attempts to transistion the PullRequestReview with the given event, if valid
  # TODO: Adding a `sig` breaks validations.
  # sig { params(event: T.any(Symbol, String), actor: T.nilable(User), message: T.nilable(String)).void }
  def trigger(event, actor: nil, message: nil)
    case event.to_sym
    when :approve
      self.approve!
    when :request_changes
      self.request_changes!
    when :comment
      self.comment!
    when :dismiss
      self.dismiss!(actor, message: message)
    end
  end

  sig { params(kwargs: T.untyped).returns(PullRequestReviewThread) }
  def build_thread(**kwargs)
    review_threads.build(pull_request: pull_request, **kwargs)
  end

  # Basically just a convenience method instead of building the thread and then the
  # comment explicitly.
  sig do
    params(
      body: String,
      position: Integer,
      path: String,
      user: T.nilable(User),
      diff: T.untyped,
      position_is_used: T.nilable(T::Boolean)
    ).returns([PullRequestReviewThread, PullRequestReviewComment])
  end
  def build_thread_with_comment(body:, position:, path:, user: nil, diff: nil, position_is_used: nil)
    thread = build_thread
    comment = thread.build_first_diff_position_comment(
      user: user,
      body: body,
      position: position,
      path: path,
      diff: diff,
      position_is_used: position_is_used
    )
    [thread, comment]
  end

  sig { returns(Promise[NilClass]) }
  def async_performed_via_integration
    Promise.resolve(nil)
  end

  # only attempt to attach matching assets when the review's body changes
  sig { returns(T::Boolean) }
  def attach_matching_assets?
    body_previously_changed?
  end

  sig { returns(T::Boolean) }
  def attach_matching_assets_in_background?
    true
  end

  # Override reading the body to guarantee returning valid utf8 encoded data.
  #
  # See also GitHub::UTF8
  sig { override.returns(T.nilable(String)) }
  def body
    utf8(read_attribute(:body))
  end

  # Instrumentation
  sig { void }
  def instrument_update_event
    return if pending?
    # This could technically fail if there are two `.save`s
    # in the same transaction. In that case, the first `previous_changes[:body]`
    # would be discarded by the second save, then the transaction would finish
    # and call this method.
    #
    # This method is tested at controller-level so we can make sure it works
    # correctly from a user's point of view.
    old_body = previous_changes[:body].try(:first)
    instrument :update, changes: { old_body: old_body, body: body }
    GlobalInstrumenter.instrument("pull_request_review.update",
      review: self,
      old_body: old_body,
    )
  end

  sig { void }
  def instrument_dismiss_event
    return if @dismisser.nil? || !dismissed? || !previous_changes.key?(:state)

    payload = {
      review_id: id,
      issue_id: T.unsafe(pull_request).issue.id,
      actor: @dismisser,
    }
    instrument(:dismiss, payload)
    GlobalInstrumenter.instrument("pull_request_review.dismiss",
      review: self,
      actor: @dismisser,
    )
    @dismisser = nil
  end

  sig { void }
  def notify_socket_subscribers
    data = {
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "pull request review ##{id} updated",
        gid: global_relay_id,
    }
    channel = GitHub::WebSocket::Channels.pull_request_review(self)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel, data)
  end

  # Returns the children items for the purposes of rendering review(s) on a timeline -
  # i.e. on PullRequest#show
  #
  # See also IssueTimeline#child_enumerator
  #
  # Returns PullRequestReviewComments
  def timeline_children
    review_comments.inject([]) do |result, comment|
      (result << comment).concat(comment.replies)
    end.uniq
  end

  sig { returns(Promise[Repository]) }
  def async_notifications_list
    async_repository
  end

  sig { returns(T.nilable(Issue)) }
  def notifications_thread
    T.must(pull_request).issue
  end

  sig { override.returns(User) }
  def notifications_author
    user || User.ghost
  end

  # Summary of the review used by notifications.
  sig { returns(String) }
  def notifications_summary_title
    "@#{notifications_author.display_login} #{state_summary} this pull request."
  end

  class InvalidStateForSummary < RuntimeError; end

  # Internal: Returns a summary of the action taken by the reviewer.
  #
  # @raises [InvalidStateForSummary]
  sig { returns(String) }
  def state_summary
    case current_state.name
    when :changes_requested
      "requested changes on"
    when :approved
      "approved"
    when :commented
      "commented on"
    when :dismissed
      "dismissed review on"
    else
      raise InvalidStateForSummary, "invalid state for summary: #{state}"
    end
  end

  def update_notification_summary?
    !pending? && super
  end

  # Overrides Summarizable#update_notification_rollup. Reviews are summarized
  # in a non-standard way, so we override this method to use the custom
  # summary method.
  #
  # summary - NotificationSummary object for the thread.
  sig { params(summary: NotificationSummary).void }
  def update_notification_rollup(summary)
    suffix = summarizable_changed?(:body) ? :changed : :unchanged
    GitHub.dogstats.increment("newsies.rollup", tags: ["type:#{suffix}"])

    summary.summarize_pull_request_review(self)
  end

  # Overrides GitHub::UserContent#mentioned_users
  #
  # Users mentioned in the body and all comments of the pull request review.
  #
  sig { returns(T::Array[User]) }
  def mentioned_users
    users = super
    review_comments.each do |comment|
      users += comment.mentioned_users
    end

    users
  end

  # Overrides GitHub::UserContent#mentioned_usernames
  #
  # User names mentioned in the body and all comments of the pull request review.
  sig { returns(T::Set[String]) }
  def mentioned_usernames
    user_names = T.let(super, T::Set[String])

    review_comments.each do |comment|
      user_names += comment.mentioned_usernames
    end

    user_names
  end

  # Overrides GitHub::UserContent#mentioned_teams
  #
  # Teams mentioned in the body and all comments of the pull request review.
  sig { returns(T::Array[Team]) }
  def mentioned_teams
    teams = super
    review_comments.each do |comment|
      teams += comment.mentioned_teams
    end

    teams
  end

  sig { void }
  def destroy_pending_comments
    review_comments.with_pending_state.destroy_all

    destroy_if_empty
  end

  # Public: destroy this PullRequestReview if there are no comments and it is not approved
  sig { void }
  def destroy_if_empty
    destroy if no_body_and_no_comments? && !approved?
  end

  # See IssueTimeline
  sig { returns(T::Array[T.nilable(ActiveSupport::TimeWithZone)]) }
  def timeline_sort_by
    [submitted_at || created_at]
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def editable_by?(user)
    return false unless user
    return true if self.user == user && !(T.must(pull_request).locked?)
    T.must(repository).pushable_by?(user)
  end

  sig { params(viewer: T.nilable(User)).returns(BooleanPromise) }
  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Array[Symbol]]) }
  def async_viewer_cannot_update_reasons(viewer)
    return T.unsafe(Promise.resolve([:login_required])) unless viewer

    Platform::Loaders::ActiveRecordAssociation.load_all(self, [:pull_request, :repository, :user]).then do
      T.must(pull_request).async_issue.then do |issue|
        issue = T.let(issue, Issue)
        T.let(issue.async_repository, Promise[T.nilable(Repository)]).then do |repository|
          User::InteractionAbility.async_interaction_allowed?(
            user: viewer,
            repository:,
          ).then do |interaction_allowed|
            errors = []
            errors << :locked if issue.locked_for?(viewer)
            errors << :insufficient_access if !editable_by?(viewer) || !interaction_allowed
            errors
          end
        end
      end
    end
  end

  sig { params(viewer: T.nilable(User)).returns(BooleanPromise) }
  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    async_viewer_can_update?(viewer)
  end

  def get_notification_summary
    return unless pull_request && pull_request&.issue

    list = Newsies::List.new("Repository", pull_request&.repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, pull_request&.issue)
  end

  sig { returns(Promise[String]) }
  def async_update_path_uri
    T.let(async_pull_request, Promise[T.nilable(PullRequest)]).then do |pull_request|
      "#{T.must(pull_request).permalink(include_host: false)}/reviews/#{id}"
    end
  end

  # Absolute permalink for this PullRequestReview
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                review.permalink(include_host: false) => `/github/github/pull/4#pullrequestreview-4`
  #
  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    "#{T.must(pull_request).permalink(include_host: include_host)}##{anchor}"
  end
  alias url permalink

  sig { returns(String) }
  def notifications_permalink
    if show_in_timeline?
      permalink
    else
      T.must(review_comments.first).permalink
    end
  end

  sig { returns(Promise[String]) }
  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_pull_request.then(&:async_path_uri).then do |path_uri|
      path_uri = path_uri.dup
      path_uri.fragment = anchor
      path_uri
    end
  end

  sig { returns(String) }
  def anchor
    "pullrequestreview-#{id}"
  end

  sig { returns(T::Boolean) }
  def writer?
    return @async_author_can_push if defined?(@async_author_can_push)

    @async_author_can_push = async_author_can_push_to_repository?.sync
  end

  sig { returns(BooleanPromise) }
  def async_author_can_push_to_repository?
    Promise.all([async_user, async_pull_request.then(&:async_repository)]).then do |user, repository|
      next false unless user && repository

      repository.async_pushable_by?(user)
    end
  end

  sig { returns(T::Boolean) }
  def author_can_push_to_repository?
    async_author_can_push_to_repository?.sync
  end

  # Public: Are all the comments on this Review a reply?
  sig { returns(T::Boolean) }
  def all_replies?
    review_comments.any? && review_comments.all?(&:reply?)
  end

  # Public: Should this review show in the timeline?
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def show_in_timeline?
    !(all_replies? && body.blank?) || !commented?
  end

  # Public: Should this review satisfy a request for review?
  # If a review is not a comment reply, pending, or the PR author then the request is satisfied
  # and should be deleted.
  sig { returns(T::Boolean) }
  def satisfies_request?
    show_in_timeline? && !pending? && T.must(pull_request).user != user
  end

  # Public: Does this review lack a body and also associated comments?
  sig { returns(T::Boolean) }
  def no_body_and_no_comments?
    body.blank? && review_comments.empty?
  end

  # Public: Retrieve list of pull request review threads for this review visible to the viewer
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Array[PullRequestReviewThread]]) }
  def async_review_threads_for(viewer)
    Platform::Loaders::PullRequestReview::ReviewThreads.load(id, viewer)
  end

  def self.sliced_threads_and_replies(threads_and_replies, pagination_options)
    if pagination_options[:after]
      threads_and_replies = threads_and_replies.drop_while do |thread|
        thread.id != pagination_options[:after]
      end.drop(1)
    end

    if pagination_options[:before]
      threads_and_replies = threads_and_replies.take_while do |thread|
        thread.id != pagination_options[:before]
      end
    end

    threads_and_replies
  end

  batch_method(:prelude_paginated_review_threads_and_replies_for) do |reviews, viewer, options|
    results = Promise.all(reviews.map do |pull_request_review|
      Promise.all([
        pull_request_review.async_review_threads_for(viewer),
        Platform::Loaders::PullRequestReviewCrossReviewReplies.load(pull_request_review.id, viewer),
      ]).then do |review_thread_models, cross_review_replies|
        items = review_thread_models.concat(cross_review_replies).sort_by { |item| [item.created_at, item.is_a?(::PullRequestReviewThread) ? 0 : 1, item.id] }
        items = sliced_threads_and_replies(items, options)

        first_group = items.take(options[:first])
        remaining_items = items.drop(options[:first])
        hidden_count = 0
        last_group = []
        if remaining_items.length > 0
          last_group = remaining_items.last(options[:last]) if options[:last]
          hidden_count = remaining_items.length - last_group.length
        end

        { first_group: first_group, last_group: last_group, hidden_items_count: hidden_count }
      end
    end).sync

    reviews.zip(results).to_h
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Array[PullRequestReviewComment]]) }
  def async_review_comments_for(viewer)
    Platform::Loaders::PullRequestReviewCommentsForReview.load(id, viewer)
  end

  # Used by HTML::Pipeline to determine what to linkify
  sig { returns(T.nilable(Repository)) }
  def entity = repository

  sig { returns(Promise[T.nilable(Repository)]) }
  def async_entity = async_repository

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def can_be_dismissed_by?(viewer)
    pull_request = T.must(self.pull_request)

    if pull_request.base_branch_rule_evaluator && pull_request.base_branch_rule_evaluator&.restricted_dismissed_reviews?
      T.must(pull_request.base_branch_rule_evaluator).review_dismissable_by?(viewer)
    else
      T.must(pull_request.repository).pushable_by?(viewer)
    end
  end

  # Public: Checks spamminess of associated pull request.
  sig { returns(T::Boolean) }
  def belongs_to_spammy_content?
    pull_request&.spammy? || false
  end

  DIFF_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/pull/{number}/files/{oid}").freeze

  # Public: Get the URI to the diff that this review was created against.
  sig { returns(Promise[String]) }
  def async_diff_uri
    promise = Promise.all([async_repository, async_pull_request]).then do |repository, pull_request|
      Promise.all([repository.async_owner, pull_request.async_issue]).then do |owner, issue|
        DIFF_URI_TEMPLATE.expand({
          owner: owner.display_login,
          name: repository.name,
          number: issue.number,
          oid: head_sha,
        })
      end
    end

    # TODO: Sorbet assumes a nested Promise is returned.
    T.unsafe(promise)
  end

  # Find all the teams on behalf of whom this review was performed.
  sig { returns(Promise[T::Array[Team]]) }
  def async_on_behalf_of_teams
    promise = async_review_requests.then do |review_requests|
      on_behalf_of_teams(review_requests).then(&:compact)
    end

    # TODO: Sorbet assumes a nested Promise is returned.
    T.unsafe(promise)
  end

  ReviewerHash = T.type_alias { T::Hash[Symbol, T.any(Team, User, T::Boolean)] }

  # Find the codeowners and teams on behalf of whom this review was performed.
  #
  # Returns Promise<Array<{reviewer: Team | User; as_codeowner: boolean}>>.
  sig { returns(Promise[T::Array[ReviewerHash]]) }
  def async_on_behalf_of_reviewers
    promise = async_review_requests.then do |review_requests|
      teams_promise = on_behalf_of_teams(review_requests)
      async_codeowner_review_requests = Promise.all(review_requests.map(&:async_as_codeowner?))

      Promise.all([async_codeowner_review_requests, teams_promise]).then do |as_codeowner_results, teams|
        on_behalf_of_teams = teams.compact.each_with_object({}) do |team, team_hash|
          team_hash[team.id] = team
        end
        result = {}
        # there can only be one user codeowner request fulfilled per review - the reviewer themself
        user_codeowner_request = T.let(nil, T.nilable(ReviewRequest))
        review_requests.zip(as_codeowner_results) do |review_request, as_codeowner|
          reviewer_id = review_request.reviewer_id
          reviewer_fulfilled_request_on_behalf_of_team = review_request.reviewer_type == "Team" && on_behalf_of_teams.include?(reviewer_id)
          user_fulfilled_request_as_codeowner = review_request.reviewer_type == "User" && as_codeowner
          if reviewer_fulfilled_request_on_behalf_of_team
            reviewer = on_behalf_of_teams[reviewer_id]
            result[reviewer.id] ||= {
              reviewer: reviewer,
              as_codeowner: as_codeowner,
            }
          elsif user_fulfilled_request_as_codeowner
            user_codeowner_request = review_request
          end
        end

        reviewers_data = result.values.to_a
        if user_codeowner_request
          user_codeowner_request.async_reviewer.then do |reviewer|
            reviewers_data.push({
              reviewer: reviewer,
              as_codeowner: true,
            })

            reviewers_data
          end
        else
          reviewers_data
        end
      end
    end

    T.unsafe(promise)
  end

  batch_method(:prelude_on_behalf_of_visible_teams_for) do |reviews, viewer|
    results = Promise.all(
      reviews.map { |review| review.async_on_behalf_of_visible_teams_for(viewer) }
    ).sync
    reviews.zip(results).to_h
  end

  # Find all the teams on behalf of whom this review was performed,
  # and which are visible to the given viewer.
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Array[Team]]) }
  def async_on_behalf_of_visible_teams_for(viewer)
    return Promise.resolve(T.unsafe([])) unless viewer

    promise = async_on_behalf_of_teams.then do |teams|
      async_team_visibilities = Promise.all(teams.map { |team| team.async_visible_to?(viewer) })

      async_team_visibilities.then do |visibilities|
        result = Set.new
        teams.zip(visibilities) { |team, visible| result.add(team) if visible }
        result.to_a
      end
    end

    # TODO: Sorbet assumes a nested Promise is returned.
    T.unsafe(promise)
  end

  # Find all the teams and users on behalf of whom this review was performed as a codeowner,
  # and which are visible to the given viewer.
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Array[ReviewerHash]]) }
  def async_on_behalf_of_visible_reviewers(viewer)
    return Promise.resolve(T.unsafe([])) unless viewer

    promise = async_on_behalf_of_reviewers.then do |reviewers|
      async_visibilities = T.let(reviewers.map do |reviewer|
        actor = reviewer[:reviewer]
        actor.respond_to?(:async_visible_to?) ? T.unsafe(actor).async_visible_to?(viewer) : Promise.resolve(true)
      end, T::Array[BooleanPromise])

      Promise.all(async_visibilities).then do |visibilities|
        result = T.let(Set.new, T::Set[ReviewerHash])
        reviewers.zip(visibilities) { |reviewer, visible| result.add(reviewer) if visible }
        result.to_a
      end
    end

    # TODO: Sorbet assumes a nested Promise is returned.
    T.unsafe(promise)
  end

  # Internal: Should we enqueue the SubscribeAndNotifyJob when the review is
  # updated?
  #
  # This method checks that we're updating an already submitted review.
  # Since reviews are updated on submission, and `subscribe_and_notify` is triggered
  # during submission, we want to avoid enqueueing a duplicate SubscribeAndNotifyJob
  # here.
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def update_subscriptions_and_notify?
    body_previously_changed? &&
      !pending? &&
      !submitted_at_previously_changed?
  end

  # Override NotificationsContent#subscribe_and_notify so that we only
  # trigger the SubscribeAndNotify job for normal PullRequestReviews.
  sig { void }
  def subscribe_and_notify
    super if !code_scanning?
  end

  # Internal: Implements the NotificationsContent#unsubscribable_users method.
  #
  # Filters out users that should keep a subscription to this thread.
  sig { params(users: T::Array[User]).returns(T::Array[User]) }
  def unsubscribable_users(users)
    pull_request = T.must(self.pull_request)
    issue = T.must(pull_request.issue)

    issue.unsubscribable_users(users)
  end

  # Override Summarizable::deliver_notifications to use submitted_at as event_time.
  sig { returns(T::Boolean) }
  def deliver_notifications
    super(event_time: submitted_at)
  end

  sig { params(actor: T.nilable(User)).returns(BooleanPromise) }
  def async_minimizable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(false) if pending?
    return Promise.resolve(true) if actor.site_admin?

    # Users can always minimize their own comments, unless they're restricted
    # by internal App policy...
    return Promise.resolve(true) if unrestricted_actor_minimizing_own_comment?(actor)

    async_repository.then do |repository|
      next false unless repository
      repository.resources.pull_requests.async_writable_by?(actor).then do |is_writable|
        next true if is_writable
        # moderators can only minimize comments in public repos
        next false unless repository.public?

        repository.async_owner.then do |owner|
          next false unless owner.organization?
          owner.async_moderator?(actor)
        end
      end
    end
  end

  sig { params(actor: T.nilable(User)).returns(BooleanPromise) }
  def async_unminimizable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(false) if pending?
    return Promise.resolve(true) if actor.site_admin?

    T.let(async_repository, Promise[T.nilable(Repository)]).then do |repo|
      next false unless repo
      repo.resources.pull_requests.async_writable_by?(actor)
    end
  end

  sig { returns(T.nilable(Integer)) }
  attr_accessor :comment_hidden_by

  sig { returns(T::Boolean) }
  def submitted?
    submitted_at.present?
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  # Added as a public accessor/'alias' for the private new_reviewer_was_added?
  # method for the CreateNewPullRequestReviewCommentOrchestration
  sig { returns(T::Boolean) }
  def new_reviewer_added?
    new_reviewer_was_added?
  end

  # Made public to support the CreateNewPullRequestReviewCommentOrchestration
  # calling this method in its `after_commit_review` step. This is the only
  # method of this name in the codebase so I believe that the chance that this
  # might be invoked in error or maliciously is very low (even if the logic
  # is more or less entirely internal to the PullRequestReview model)
  sig { void }
  def notify_state_changed
    channel = GitHub::WebSocket::Channels.pull_request_review_state(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(
      pull_request,
      channel,
      { review_id: id, state: current_state.name,
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait },
    )
  end

  # Made public to support the CreateNewPullRequestReviewCommentOrchestration
  # calling this method in its `after_commit_review` step. This is the only
  # method of this name in the codebase so I believe that the chance that this
  # might be invoked in error or maliciously is very low (even if the logic
  # is more or less entirely internal to the PullRequestReview model)
  sig { void }
  def trigger_review_decision_updated
    return if GitHub.enterprise?
    return unless pull_request = self.pull_request
    return if !pull_request.user&.feature_enabled?(:pull_request_sub_triggers)

    Platform::Schema.subscriptions.trigger(
      :pull_request_review_decision_updated,
      { id: pull_request.global_relay_id }
    )
  end

  # Private: handle a successfully submitted PullRequestReview. This fires "on_entry"
  # to the submitted state, which means that the state has been successfully
  # transitioned to and persisted.
  #
  sig { returns(T.nilable(T::Boolean)) }
  private def after_submission
    return if skip_review_callbacks?

    GitHub.dogstats.time("pull_request_review.after_submission") do
      Rails.logger.debug { "[submission] after_submission for #{self} in #{current_state}" }
      return false unless valid?

      pending_comments = review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull_request])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)

      fulfill_requested_review
      @call_after_commit = true
      Rails.logger.debug { "[submission] after_submission for #{self} completed" }
      true
    end
  end

  sig { void }
  private def publish_live_update_for_merge_box
    channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
  end

  # Private: Should after_commit callbacks be run? This is set after_submission
  # completes successfully.
  sig { returns(T.nilable(T::Boolean)) }
  private def call_after_commit?
    @call_after_commit
  end

  # Private: Run after_commit logic.
  sig { void }
  private def after_commit
    return if skip_review_callbacks?

    # Common GUID needed in order to track parity between tier1 events
    # and events-v1
    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)

    pull_request = T.must(self.pull_request)

    payload = {
      id: id,
      state: state,
      issue_id: T.must(pull_request.issue).id,
      actor: user,
      pull_request_author: pull_request.user,
      new_reviewer_was_added: new_reviewer_was_added?,
      event_guid: event_guid
    }

    instrument(:submit, payload)
    GlobalInstrumenter.instrument("pull_request_review.submit", review: self, importing: importing?)
    Events::PullRequestReviewPublisher.submitted(self, event_guid: event_guid)

    submitted_comments = review_comments.with_submitted_state
    GitHub::PrefillAssociations.prefill_associations(submitted_comments, :pull_request, available_records: [pull_request])
    submitted_comments.each { |review_comment| review_comment.allowed = allowed? }
    submitted_comments.each(&:instrument_submission)

    subscribe_and_notify unless importing?
    pull_request.notify_socket_subscribers
    pull_request.synchronize_search_index

    if state_previously_changed? && current_state > :commented
      notify_state_changed
      trigger_review_decision_updated
    end

    @call_after_commit = false
  end

  sig { returns(T::Boolean) }
  private def new_reviewer_was_added?
    if previously_submitted_review_author_ids
      (submitted_review_author_ids - previously_submitted_review_author_ids).any?
    else
      true
    end
  end

  sig { void }
  private def call_auto_merge_job_enqueuer
    if approved? || commented? || dismissed?
      T.must(pull_request).enqueue_auto_merge_job_if_enabled
    end
  end

  sig { params(review_requests: T::Array[ReviewRequest]).returns(Promise[T::Array[T.nilable(Team)]]) }
  private def on_behalf_of_teams(review_requests)
    team_review_requests = review_requests.select do |request|
      request.reviewer_type == "Team"
    end

    on_behalf_of_team_ids = team_review_requests.map(&:reviewer_id)
    Platform::Loaders::ActiveRecord.load_all(::Team, on_behalf_of_team_ids)
  end

  # Called on approve! before persistence.
  protected def approve(*args, **kwargs)
    pull_request = T.must(self.pull_request)

    if pull_request.user == user
      return halt "Can not approve your own pull request"
    end

    if !pull_request.allows_non_comment_reviews_from?(reviewer: user)
      return halt "Can not approve a pull request without explicit repository access"
    end

    if pull_request.user_has_violated_push_rule?(user)
      return halt "Can not approve a pull request you pushed to after it was opened"
    end

    if pull_request_with_dismiss_stale_reviews_has_changed?
      return halt "This pull request has been updated since you started reviewing. Please review the latest changes and resubmit."
    end

    set_submitted_at
    nil
  end

  # Called on comment! before persistence.
  protected def comment(*args, **kwargs)
    return if skip_review_callbacks?

    if no_body_and_no_comments?
      return halt(NEEDS_COMMENTS_WHEN_REQUESTING_CHANGES)
    end

    set_submitted_at
    nil
  end

  # Called on request_changes! before persistence.
  protected def request_changes(*args, **kwargs)
    pull_request = T.must(self.pull_request)

    if no_body_and_no_comments?
      return halt NEEDS_COMMENTS_WHEN_REQUESTING_CHANGES
    end

    if pull_request.user == user
      return halt "Can not request changes on your own pull request"
    end

    if !pull_request.allows_non_comment_reviews_from?(reviewer: user)
      return halt "Can not request changes on a pull request without explicit repository access"
    end

    set_submitted_at
    nil
  end

  # Protected: Guards against invalid dismiss! events. This is automatically
  # invoked by the Workflow before the state transistion happens.
  #
  # message         - (Optional) A String describing why the review was dismissed.
  # via_commit_oid  - (Optional) May be provided instead of a message if the
  #                   review was automatically dismissed due to new changes
  #                   being pushed.
  sig { params(user: User, message: T.nilable(String), via_commit_oid: T.nilable(String)).void }
  protected def dismiss(user, message: nil, via_commit_oid: nil)
    pull_request = T.must(self.pull_request)

    if !pull_request.open?
      return halt "Can only dismiss reviews on open pull requests"
    end

    if message.blank? && via_commit_oid.blank?
      return halt "A message or commit OID is required to dismiss a review"
    end

    pull_request.events.create(
      event: "review_dismissed",
      actor_id: user.id,
      pull_request_review_state_was: state,
      pull_request_review_id: id,
      after_commit_oid: via_commit_oid,
      message: message,
    )
    @dismisser = user
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(actor)
    async_pull_request.then do |pull_request|
      next false unless pull_request
      pull_request.async_readable_by?(actor)
    end
  end

  # Overrides NotificationsContent#defer_loading_mentions? to defer loading
  # mentioned users and teams to background jobs to increase performance
  sig { returns(T::Boolean) }
  def defer_loading_mentions?
    true
  end

  # Public: Has the pull request this review was left on changed since
  #         the review was submitted?
  sig { returns(T::Boolean) }
  def pull_request_has_changed?
    head_sha != T.must(pull_request).head_sha
  end

  # Public: Has the pull request with the dismiss stale review branch protection been updated
  #         since it was last reviewed?
  sig { returns(T.nilable(T::Boolean)) }
  def pull_request_with_dismiss_stale_reviews_has_changed?
    pull_request = T.must(self.pull_request)

    pull_request_has_changed? &&
      pull_request.base_branch_rule_evaluator &&
      T.must(pull_request.base_branch_rule_evaluator).dismiss_stale_reviews_on_push?
  end

  # Public: Does this review's head_sha still appear in the pull request's
  #         changed commits?
  sig { returns(T::Boolean) }
  def applies_to_current_diff?
    return @applies_to_current_diff if defined?(@applies_to_current_diff)
    @applies_to_current_diff = T.must(pull_request).changed_commit_oids.include?(head_sha)
  rescue GitRPC::ObjectMissing
    false
  end

  # Public: List of changed commit oids following the review's head_sha.
  sig { returns(T::Array[String]) }
  def pull_request_oids_since
    return @pull_request_oids_since if defined?(@pull_request_oids_since)

    pull_request = T.must(self.pull_request)
    index = pull_request.changed_commit_oids.index(head_sha)
    index ||= -1 # If head_sha isn't in changed_commits we want them all.
    @pull_request_oids_since = pull_request.changed_commit_oids.from(index + 1)
  end

  sig { returns(T::Boolean) }
  def show_in_sidebar?
    !code_scanning?
  end

  sig { returns(Issue) }
  def pull_request_issue
    T.must(T.must(pull_request).issue)
  end

  alias :referrer :pull_request_issue

  sig { returns(T::Boolean) }
  def track_references?
    submitted?
  end

  sig { returns(T::Boolean) }
  def track_references_in_background?
    true
  end

  sig { returns(T.nilable(T::Boolean)) }
  def allowed?
    return @allowed if defined?(@allowed)
    @allowed = user && pull_request&.repository&.permit?(user, :write)
  end

  private

  def variant_type_supports_user
    return if user_id.nil?

    user = self.user
    return if user.nil?

    if copilot? && !user.bot?
      errors.add(:user, "must be a bot for a Copilot review")
    end
  end

  # Private: log reviews that are missing merge base shas
  sig { void }
  def log_missing_merge_base_sha
    return unless merge_base_sha.nil?
    # We are only logging on create and update
    # This is run on after_commit, so look at 'previously_changed'
    action = id_previously_changed? ? :create : :update

    GitHub.dogstats.increment("pull_request_review.missing_merge_base_sha", tags: ["action:#{action}"])
    GitHub.logger.info("Missing merge base sha for review", {
      "gh.pull_request.review.head_sha": head_sha,
      "gh.pull_request.base_sha": T.must(pull_request).base_sha,
      "gh.actor.id": user_id,
      "gh.pull_request.review.id": id,
      "gh.pull_request.review.state": state,
      "db.transaction.type": action,
      "gh.pull_request.id": pull_request_id,
      "gh.repo.id": repository&.id,
      "gh.repo.owner_id": repository&.owner_id,
      "code.callstack": caller
    })
  end

  # Private: Update the `reviews_with_body_count` attr on `PullRequest` model
  sig { void }
  def update_pull_request_counters
    return if pull_request.nil?
    return if pending?

    T.must(pull_request).update_review_and_comment_counts
  end

  sig { void }
  def trigger_platform_subscriptions
    return if pull_request.nil?

    # trigger when a review is submitted with a body
    if body_previously_changed? && submitted_at_previously_changed?
      actor = User.find_by(id: GitHub.context[:actor_id])
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
        Platform::Schema.subscriptions.trigger(
          :pull_request_comments_updated,
          { id: T.must(pull_request).global_relay_id }
        )
      end
    end
  end

  # Private: set submitted_at
  sig { void }
  def set_submitted_at
    self.submitted_at = Time.zone.now
  end

  # Private: Do any necessary before_validation processing. All before_validation
  # logic should be called from this method.
  sig { void }
  def set_repository_id
    self.repository_id = pull_request&.repository_id
  end

  sig { void }
  private def set_previously_submitted_review_author_ids
    return unless submitted_at_changed? && submitted_at_was.nil?
    self.previously_submitted_review_author_ids = submitted_review_author_ids
  end

  sig { returns(T::Array[Integer]) }
  private def submitted_review_author_ids
    self
      .class
      .submitted
      .not_spammy
      .where(pull_request_id: pull_request_id)
      .select(:user_id)
      .distinct
      .pluck(:user_id)
  end

  # Private: Do any necessary after_create processing. All after_create
  # logic should be called from this method.
  sig { void }
  def after_create
    GitHub.dogstats.increment("pull_request_review", tags: ["action:create"])

    # clear_caches_for_user writes to the mysql 5 cluster, which might be surprising to the caller
    # so ensure that we have a write connection.
    ActiveRecord::Base.connected_to(role: :writing) { Contribution.clear_caches_for_user(user) }

    GlobalInstrumenter.instrument("pull_request_review.create", {
      repository: T.must(pull_request).repository,
      review: self,
    })
  end

  sig { void }
  def after_destroy_commit
    instrument(:delete)
    destroy_notification_summary if related_repo_exists_when_defined
  end

  sig { void }
  def after_dismissal
    trigger_review_decision_updated
  end

  # Private: Subscribe the author of the review
  sig { void }
  def subscribe_author
    subscribe(user, :comment)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def validate_body_is_editable
    if code_scanning?
      errors.add(:body, "is not editable")
      return false
    end

    true
  end

  # Private: enforce one pending review per [User / Pull Request]
  sig { returns(T.nilable(T::Boolean)) }
  def one_pending_review_per_user_and_pull_request
    dupes = self.class.default_scoped.where(state: 0, pull_request_id: pull_request_id, user_id: user_id)
    dupes = dupes.where("id <> ?", id) if persisted?
    if dupes.exists?
      errors.add(:user_id, "can only have one pending review per pull request")
    end

    nil
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      review: self,
      spammy: user&.spammy?,
      pull_request: pull_request,
      body: body,
      allowed: allowed?,
      repo: pull_request&.repository,
      business: pull_request&.repository&.business,
      org: pull_request&.repository&.organization,
    }
  end

  # Private: Validation to see if review is allowed based on pull request lock
  # Only someone allowed to push to the repository can comment on a locked pull request
  # (unlocked pull requsts have no such restriction)
  sig { returns(T.nilable(T::Boolean)) }
  def validate_pull_request_lock
    pull_request = T.must(self.pull_request)

    return true unless T.must(pull_request.issue).locked?
    return true if T.must(pull_request.repository).pushable_by?(user)

    errors.add(:base, "lock prevents review")

    nil
  end

  # Private: Is there an explanation needed along with this review? An explanation
  # means _either_ body text on the review or associated review_comments.
  sig { returns(T::Boolean) }
  def explanation_required?
    commented? || changes_requested?
  end

  # Private: Validation to see if the review has a necessary explanation.
  #
  # Returns nothing.
  sig { returns(T.nilable(T::Boolean)) }
  def explanation_exists?
    # The explanation can either be a review body or comments.
    return true if body.present? || review_comments.present?

    errors.add(:body, "required for pull request reviews that are comments or requesting changes")

    nil
  end

  # Private: Validation to ensure the creator of this review is not blocked
  sig { void }
  def ensure_creator_is_not_blocked
    return unless pull_request = self.pull_request
    return unless user = self.user

    if pull_request.blocked_from_reviewing?(user)
      errors.add(:user, "is blocked")
    end
  end

  # Private: Satisfy a ReviewRequest via this PullRequestReview
  sig { void }
  def fulfill_requested_review
    return unless satisfies_request?
    pull_request = T.must(self.pull_request)

    fullfilled_team_requests = pull_request.team_requests_on_behalf_of(user)
    return unless fullfilled_team_requests.any? || pull_request.review_requested_for?(user)

    pending_requests = pull_request.review_requests_for(user)
    pending_or_fulfilled_requests = [fullfilled_team_requests, pending_requests].compact.reduce([], :|)
    self.review_requests = pending_or_fulfilled_requests
    ReviewRequest.where(id: pending_or_fulfilled_requests.map(&:id)).update_all(deferred: false)
  end

  # Private: Override workflow-orchestrator gem to use update_attributes instead of
  # update_column - this ensures that standard Rails callbacks still fire.
  sig { params(new_value: T.untyped).void }
  def persist_workflow_state(new_value)
    update self.class.workflow_column => new_value
  end

  # Private: Override process_event! to wrap everything in a transaction.  We need
  # to do this to ensure a deterministic order of callbacks when events are fired.
  #
  # This ensures the following reliable order for a call like review.approve!:
  #
  #  BEGIN (transaction)
  #    * before_transition
  #    * approve (i.e. action method)
  #    * on_transition
  #    * on_exit
  #    * persist_workflow_state
  #    * on_entry
  #    * after_transition
  #  COMMIT
  #  after_commit (active_record))
  #
  # If we didn't do this, you could end up with the following confusing chain of
  # events (note the difference in when after_commit vs on_entry happens):
  #
  #    * before_transition
  #    * approve (i.e. action method)
  #    * on_transition
  #    * on_exit
  #    BEGIN (transaction)
  #    * persist_workflow_state
  #    COMMIT
  #    * after_commit (active_record)
  #    * on_entry
  #    * after_transition
  def process_event!(name, *args, **kwargs)
    self.transaction do
      super
    end
  end

  # Override Summarizable#author_subscribe_reason.
  sig { returns(String) }
  def author_subscribe_reason
    "comment"
  end

  sig { override.returns(MemexProjectOrRepository) }
  def saved_reply_copy_target
    self.repository
  end
end
