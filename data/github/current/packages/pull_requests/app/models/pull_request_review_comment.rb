# typed: true
# frozen_string_literal: true

class PullRequestReviewComment < ApplicationRecord::Domain::IssuesPullRequests
  extend T::Sig

  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include GitHub::Relay::GlobalIdentification
  include GitHub::MinimizeComment
  include LegacyImportable

  include Instrumentation::Model
  include EmailReceivable
  include NotificationsContent::WithCallbacks
  include Reaction::Subject::RepositoryContext
  include Referrer
  include Spam::Spammable
  include UserContentEditable
  include InteractionBanValidation
  include AuthorAssociable
  include OrgBlockable
  include AbuseReportable
  include Reactable
  include Prefillable
  include PreloadableAttributes
  include GitHub::Memoizer
  include Storage::UserAssetTransfer::SavedReplyCopyDependency
  include LastModifiedCalculation

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::IssueComment

  attr_preloadable  :report_count, :top_report_reason, :last_reported_at, :author_association_symbol

  POSITIONING_ATTRS = %w(
    path
    commit_id
    diff_hunk
    position
    original_commit_id
    original_position
    original_base_commit_id
    original_start_commit_id
    original_end_commit_id
    blob_position
    blob_path
    blob_commit_oid
    left_blob
    outdated
    start_position_offset
    subject_type
  ).freeze

  enum :state, {
    pending: 0,
    submitted: 1,
  }

  # Callers should never set the state directly. See submit! for changing
  # a pending PullRequestReviewComment to a submitted state...or better yet,
  # call workflow methods on the associated PullRequestReview.
  def state=(val)
    super
  end
  private :state=

  belongs_to :pull_request, inverse_of: :review_comments
  belongs_to :pull_request_review, inverse_of: :review_comments
  belongs_to :pull_request_review_thread, inverse_of: :review_comments, autosave: true
  belongs_to :repository
  belongs_to :user

  attr_accessor :skip_destroy_callbacks
  alias_method :skip_destroy_callbacks?, :skip_destroy_callbacks

  # Creating a reply comment performs a subset of the PullRequestReviewCommentsController#create
  # action, and invokes create validations and callbacks.
  # As we work through migrating callback logic to orchestration, this attr/method is
  # intended to differentiate between logic handled by the CreateReplyPullRequestReviewCommentOrchestration
  # and the CreateNewPullRequestReviewCommentOrchestration.

  attr_accessor :skip_reply_callbacks
  def skip_reply_callbacks?
    skip_reply_callbacks
  end

  attr_accessor :skip_create_callbacks
  def skip_create_callbacks?
    skip_create_callbacks
  end

  # Virtual column ( body is not null or body > '')
  attr_readonly :has_body

  setup_spammable(:user)

  # NOTE: If you try to load this association dynamically, your query will probably
  # time out!
  #
  # This generates a query against the pull_request_review_comments table containing
  # `where reply_to_id=?`, which causes a full table scan over all comment
  # records. There is an index on `reply_to_id`; however, there are too few records
  # containing a value, all legacy comments have NULL, so the query planner does not
  # use it, preferring a slow table scan.
  #
  # Solutions:
  #
  #   - Remove this association so we don't accidentally query the column.
  #   - Include `where pull_request_id=?` in the query to trigger a better index.
  #   - Use `force index` to tell the planner we really do want to use reply_to_id's index.
  #   - Backfill legacy comments reply_to_id values based on their path and position data.
  has_many :replies, foreign_key: :reply_to_id, class_name: "PullRequestReviewComment", inverse_of: :in_reply_to
  belongs_to :in_reply_to, foreign_key: :reply_to_id, class_name: "PullRequestReviewComment", inverse_of: :replies

  # Scoped association for eager loading with `includes`.
  # rubocop:todo Rails/InverseOf
  has_many :submitted_replies,
    -> { submitted },
    foreign_key: :reply_to_id,
    class_name: "PullRequestReviewComment"
  # rubocop:enable Rails/InverseOf

  has_many :reactions, class_name: "PullRequestReviewCommentReaction"

  before_validation :assign_repository_from_pull_request, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (skip_reply_callbacks? || skip_create_callbacks?) }

  before_validation :ensure_state_is_set, unless: -> { T.bind(self, PullRequestReviewComment); (skip_reply_callbacks? || skip_create_callbacks?) }

  validates_presence_of :body, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validates :state, presence: true, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validate :user_can_interact, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :code_scanning_variant_body_cannot_be_edited, on: :update, if: :body_changed?

  after_validation :instrument_failed_validation, on: :create, if: lambda { T.bind(self, PullRequestReviewComment); errors.any? && !(skip_create_callbacks? || skip_reply_callbacks?) }

  # If we're creating comments in bulk via the APIs executing these after_commits can cause timeouts so we skip them
  # and do them in a background job, see ReviewCommentBulkCreationCallbacksJob. We shouldn't rely on AR dirty
  # attributes in these methods as they will be cleared by the time the async background job runs.
  attr_accessor :bulk_creating

  def after_commit_on_create_callbacks
    instrument_creation
    subscribe_and_notify unless importing?
    update_pull_request_counters
    trigger_platform_subscriptions
    subscribe_to_issue
  end
  after_create_commit :after_commit_on_create_callbacks, unless: -> { T.bind(self, PullRequestReviewComment); (bulk_creating || skip_create_callbacks? || skip_reply_callbacks?) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # spam check on create handled by Newsies::DeliverNotificationsJob
  after_update_commit :enqueue_check_for_spam,  if: :check_for_spam? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_update_commit :instrument_update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :notify_socket_subscribers, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_destroy :generate_webhook_payload, if: -> { T.bind(self, PullRequestReviewComment); (send_deleted_webhook? && !skip_destroy_callbacks?) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_destroy :generate_issue_event, unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :queue_webhook_delivery, if: -> { T.bind(self, PullRequestReviewComment); (send_deleted_webhook? && !skip_destroy_callbacks?) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_destroy_commit :instrument_deletion, unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :clean_up_review_and_review_thread, unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :unresolve_thread_if_not_conversation, unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :reparent_replies, unless: -> { T.bind(self, PullRequestReviewComment); (reply? || skip_destroy_callbacks?) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_update_commit :update_subscriptions_and_notify # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_pull_request_counters, on: [:update, :destroy], unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :trigger_platform_subscriptions, on: [:update, :destroy], unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :touch_pull_request_after_commit, unless: -> { T.bind(self, PullRequestReviewComment); (skip_destroy_callbacks? || skip_create_callbacks? || skip_reply_callbacks?) }# rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validate :validate_pull_request_lock, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validate :validate_authorized_to_create_content, unless: -> { T.bind(self, PullRequestReviewComment); (importing? || skip_create_callbacks? || skip_reply_callbacks?) }
  validate :ensure_creator_is_not_blocked, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }
  validates :pull_request_review_thread, presence: true, unless: -> { T.bind(self, PullRequestReviewComment); (skip_create_callbacks? || skip_reply_callbacks?) }

  validate :validate_review_is_pending, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (importing? || skip_create_callbacks? || skip_reply_callbacks?) }
  validate :validate_reply_relations, on: :create, unless: -> { T.bind(self, PullRequestReviewComment); (importing? || skip_create_callbacks? || skip_reply_callbacks?) }

  before_destroy :validate_can_be_deleted, prepend: true, unless: :skip_destroy_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :has_body, -> { where(has_body: true) }
  scope :with_pending_state, -> { pending }
  scope :with_submitted_state, -> { submitted }

  scope :since, -> (time) {
    where("pull_request_review_comments.updated_at >= ?", time)
  }
  scope :sorted_by, -> (order_str, direction) {
    if order_str.present?
      primary_column =
        case order_str
        when /created/
          "pull_request_review_comments.created_at"
        when /updated/
          "pull_request_review_comments.updated_at"
        else
          "pull_request_review_comments.created_at"
        end

      sort_direction = (direction == "asc" ? :asc : :desc)
      order(
        primary_column => sort_direction,
        "pull_request_review_comments.id" => sort_direction
      )
    else
      order("pull_request_review_comments.created_at DESC")
    end
  }

  scope :cross_review_replies, -> {
    joins(:pull_request_review_thread).where(<<~SQL)
      `pull_request_review_threads`.`pull_request_review_id` != `pull_request_review_comments`.`pull_request_review_id`
    SQL
  }

  # Public: Scope to filter comments visible to the viewer
  #
  # viewer - User viewing the comments (nil means anonymous)
  #
  # Notice: This logic needs to be kept in sync with `#visible_to?`.
  scope :visible_to, -> (viewer) {
    in_viewable_state_for(viewer).
    filter_spam_for(viewer)
  }

  scope :in_viewable_state_for, lambda { |user|
    if user
      clause = <<-SQL
        pull_request_review_comments.user_id = ?
        OR pull_request_review_comments.state = ?
      SQL

      where(clause, user.id, states[:submitted])
    else
      clause = <<-SQL
        pull_request_review_comments.state = ?
      SQL

      where(clause, states[:submitted])
    end
  }

  scope :on_line, -> {
    joins(:pull_request_review_thread).where(pull_request_review_thread: { subject_type: "line" })
  }

  enum :comment_hidden_by, GitHub::MinimizeComment::ROLES

  # determines if `position` attribute has been set for a PullRequestReviewComment record
  # currently it's only being set at record creation via REST API
  # In order to determine the usage of `position` attribute via datadot for https://github.com/github/pull-requests/issues/4808
  # it can be extended later for other usage if needed
  attr_accessor :position_is_used

  attr_writer :allowed
  def allowed?
    @allowed || pull_request&.repository&.permit?(user, :write)
  end

  def self.with_submitted_state
    where("pull_request_review_comments.state = ?", states[:submitted])
  end

  def safe_user
    user || User.ghost
  end

  # Override reading the body to guarantee returning valid utf8 encoded data.
  #
  # See also GitHub::UTF8
  def body
    utf8(read_attribute(:body))
  end

  # Override async_body_context to insert the comment's current line number,
  # only if the body contains a suggestion.
  #
  # Returns Promise that resolves to `context` object
  memoize def async_body_context
    return super unless body_may_contain_suggestion?

    Promise.all([super, async_pull_request_review_thread, async_pull_request]).then do |context, thread, pull|
      pull.async_current_threads_diff.then do |diff|
        if !diff
          context
        else
          Promise.all([thread.async_start_line(diff), thread.async_current_line(diff)]).then do |start_line, current_line|
            if start_line && start_line.current
              context.update(start_line_number: start_line.current)
            elsif current_line
              context.update(start_line_number: current_line + 1)
            end
            context
          end
        end
      end
    end
  end

  # alias_method :async_reactable_by?, :async_viewer_can_react?
  def async_reactable_by?(viewer)
    async_viewer_can_react?(viewer)
  end

  # alias_method :entity, :repository
  def entity
    repository
  end

  # alias_method :async_entity, :async_repository
  def async_entity
    async_repository
  end

  def issue
    pull_request.try(:issue)
  end

  setup_attachments
  setup_referrer

  # Override NotificationsContent#subscribe_and_notify so that we only
  # trigger the SubscribeAndNotify job for submitted legacy comments.
  def subscribe_and_notify
    super if submitted? && legacy_comment?
  end

  # Override Summarizable#deliver_notifications? for special case
  # behavior for pull_request_reviews.  See https://github.com/github/workflow/issues/426
  # for more information.
  #
  # Returns Boolean indicating if a notifications should send an email.
  def deliver_notifications?
    submitted? && legacy_comment?
  end

  # Public: Should the update_notification_summary happen?
  #
  # Overridding default behavior from Summarizable so that notification
  # summaries only get updated for submitted comments.
  #
  # Returns Boolean-ish
  def update_notification_summary?
    if legacy_comment?
      related_repo_exists_when_defined
    else
      false
    end
  end

  def pull_destroyed?
    pull_request.nil? || pull_request&.destroyed?
  end

  def code_scanning?
    async_code_scanning?.sync
  end

  def async_code_scanning?
    async_pull_request_review.then do |pull_request_review|
      !!pull_request_review&.code_scanning?
    end
  end

  def copilot?
    async_copilot?.sync
  end

  def async_copilot?
    async_pull_request_review.then do |pull_request_review|
      !!pull_request_review&.copilot?
    end
  end

  def async_reactable?
    async_code_scanning?.then do |code_scanning|
      !code_scanning
    end
  end

  # Override NotificationsContent#update_subscriptions_and_notify
  #
  # When review comments are edited, we want to trigger the
  # SubscribeAndNotifyJob with the comment's review.
  def update_subscriptions_and_notify
    if legacy_comment?
      super
    else
      return unless submitted? && body_previously_changed?

      UpdateSubscriptionsAndNotifyJob.perform_later(
        subject: pull_request_review,
        previous_body: body_previous_change,
        deliver_notifications: ::GitHub.send_notifications?,
      )
    end
  end

  def submitted_at
    async_submitted_at.sync
  end

  def async_submitted_at
    async_pull_request_review.then do |pull_request_review|
      if pull_request_review
        pull_request_review.submitted_at
      else
        created_at
      end
    end
  end

  # Unique identifier for this comment used in email notifications.
  def message_id
    "<#{T.must(repository).name_with_display_owner}/pull/#{T.must(pull_request).number}/r#{id}@#{GitHub.urls.host_name}>"
  end

  # Public: Visiblity check for comment
  #
  # viewer - User viewing the threads (nil means anonymous)
  #
  # Notice: This logic needs to be kept in sync with the scope `visible_to`.
  def visible_to?(viewer)
    return true if viewer && viewer.id == user_id
    return true if viewer && viewer.site_admin?

    submitted? && !hide_from_user?(viewer)
  end

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

  def async_unminimizable_by?(actor)
    return Promise.resolve(false) if pending?
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

  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    async_viewer_cannot_delete_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_delete_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([
      async_pull_request.then(&:async_issue).then { |issue| issue.async_locked_for?(viewer) },
      async_deletable_by?(viewer),
    ]).then do |locked, deletable|
      errors = []
      errors << :locked if locked
      errors << :insufficient_access unless deletable
      errors
    end
  end

  def async_deletable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_repository.then do |repository|
      next false unless repository

      async_user.then do |user|
        user ||= User.ghost
        next true if user == viewer

        repository.async_writable_by?(viewer)
      end
    end
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([
      async_pull_request.then(&:async_issue).then { |issue| issue.async_locked_for?(viewer) },
      async_editable_by?(viewer),
    ]).then do |locked, editable|
      errors = []
      errors << :locked if locked
      errors << :insufficient_access unless editable
      errors
    end
  end

  # TODO: The logic in this method should probably be moved into the `ContentAuthorizer` framework,
  #       but that is not async-aware yet and does not support `PullRequestReviewComment` objects,
  #       so this is the best place for this right now.
  #
  #       See `IssueComment#async_editable_by?` for a similar check on `IssueComment`s.
  def async_editable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_repository.then do |repository|
      next false unless repository

      async_user.then do |user|
        next false unless user

        User::InteractionAbility.async_interaction_allowed?(
          user: viewer,
          repository: repository,
        ).then do |interaction_allowed|
          next false unless interaction_allowed

          repository.async_owner.then do |owner|
            Promise.all([
              user.async_blocked_by?(owner),
              user.async_blocked_by?(viewer),
              viewer.async_blocked_by?(user),
            ]).then do |user_blocked_by_owner, user_blocked_by_viewer, viewer_blocked_by_user|
              next false if user_blocked_by_owner || user_blocked_by_viewer || viewer_blocked_by_user
              next true if user == viewer

              repository.async_writable_by?(viewer)
            end
          end
        end
      end
    end
  end

  def async_performed_via_integration
    Promise.resolve(nil)
  end

  # Public: return true if the user can delete this comment, falsey otherwise
  #
  # This may be the same as `editable_by?`, but duplicating for clarity and explicitness
  def deleteable_by?(user)
    self.user == user || T.must(repository).pushable_by?(user)
  end

  # Possible DeprecatedPullRequestReviewThread parent association.
  # Caution: Will only be set if loaded from a DeprecatedPullRequestReviewThread finder.
  attr_accessor :thread

  # Absolute permalink URL for this pull request.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                pull_request_review_comment.permalink(include_host: false) => `/github/github/pull/4#discussion_r123`
  #
  def permalink(include_host: true)
    "#{T.must(pull_request).permalink(include_host: include_host)}##{CommentsHelper::DISCUSSION_DOM_ID_PREFIX}#{id}"
  end
  alias url permalink

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_pull_request.then(&:async_path_uri).then do |path_uri|
      path_uri = path_uri.dup
      path_uri.fragment = "#{CommentsHelper::DISCUSSION_DOM_ID_PREFIX}#{id}"
      path_uri
    end
  end

  def async_original_diff_path_uri
    return @async_original_diff_path_uri if defined?(@async_original_diff_path_uri)

    @async_original_diff_path_uri = loaded_pull_request_review_thread.async_original_pull_request_comparison.then do |pull_request_comparison|
      next unless pull_request_comparison

      async_pull_request.then(&:async_path_uri).then do |path_uri|
        path_uri = path_uri.dup

        path_uri.path += if pull_request_comparison.range?
          "/files/#{pull_request_comparison.start_commit.oid}..#{pull_request_comparison.end_commit.oid}"
        else
          "/files/#{pull_request_comparison.end_commit.oid}"
        end

        path_uri.fragment = "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{id}"
        path_uri
      end
    end
  end

  def async_current_diff_path_uri
    @async_current_diff_path_uri ||= Promise.all([T.unsafe(self).async_outdated, async_pull_request]).then do |is_outdated, pull|
      if is_outdated
        Promise.resolve(nil)
      else
        pull.async_path_uri.then do |path_uri|
          path_uri = path_uri.dup
          path_uri.path += "/files"
          path_uri.fragment = "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{id}"
          path_uri
        end
      end
    end
  end

  def async_update_path_uri
    return @async_update_path_uri if defined?(@async_update_path_uri)

    @async_update_path_uri = async_pull_request.then(&:async_path_uri).then do |path_uri|
      path_uri = path_uri.dup
      path_uri.path += "/review_comment/#{id}"
      path_uri
    end
  end

  def last_modified_at
    @last_modified_at ||= last_modified_with :user
  end

  def subscribe_mentioned(mentions = mentioned_users, author = user)
    issue.subscribe_mentioned(mentions, author)
  end

  def unsubscribable_users(users)
    issue.unsubscribable_users(users)
  end

  # Collect conditions under which we don't bother checking the content
  # of this Issue for spam.
  def skip_spam_check?
    repository.nil?          ||   # If the repo is gone
    repository&.private?     ||   # Leave private repos alone.
    user.nil?                ||
    !user&.can_be_flagged?   ||   # No point in checking these,
    user&.spammy?            ||   # since nothing will change.
    repository&.member?(user)     # Don't bother repo members.
  end

  def check_for_spam?
    persisted? && !skip_spam_check?
  end

  # Check the comment for spam
  #
  # options - currently unused
  def check_for_spam(options = {})
    return if skip_spam_check?

    if reason = GitHub::SpamChecker.test_comment(self)
      GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:pull_request_review_comment"]

      GitHub::SpamChecker.notify "Pushing #{user&.login} for review: #{reason}"
      GlobalInstrumenter.instrument(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: user&.global_relay_id,
          additional_context: "RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT",
          origin: :RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT,
          queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
        },
      )
    end
  end

  # Internal: associate a PullRequestReview with this comment, and make sure the
  # state is in sync.  NOTE: This does not save the comment - the caller is
  # responsible for that.
  #
  # Returns the PullRequestReviewComment
  def add_review_for(user:, pull_request:, head_sha:)
    review = pull_request.reviews.with_pending_state.where(user_id: user.id).first ||
             pull_request.reviews.with_pending_state.create!(user_id: user.id, head_sha: head_sha,
               merge_base_sha: pull_request.find_best_merge_base_sha(head_sha: head_sha))
    review.review_comments << self
    self.pull_request_review = review
    self.state = :pending
    self
  end

  # Internal: save! and submit this comment.  This will raise if
  # the save on the comment fails for some reason.
  #
  # Returns the PullRequestReviewComment
  def submit!
    raise "Cannot submit a comment twice!" if submitted?
    self.state = :submitted
    self.save!
    self
  end

  # Public: Is this PullRequestReviewComment a reply? Note that we only
  # began tracking reply_to_id around August 2016.  Older comments
  # were "replies" only in the sense that they were created on the same
  # file / line / position on a PR.
  #
  # Returns a Boolean
  def reply?
    reply_to_id.present?
  end

  # Public: Is this PullRequestReviewComment a legacy comment?
  #
  # We classify a legacy comment as any comment that DOES NOT have
  # a PullRequestReview associated with it.
  def legacy_comment?
    pull_request_review_id.nil?
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_readable_by?(actor)
    async_pull_request.then do |pull_request|
      next false unless pull_request
      pull_request.async_readable_by?(actor)
    end
  end

  def notifications_author
    user
  end

  # alias_method :notifications_list, :repository
  def notifications_list
    repository
  end

  # Tell notifications about our thread structure.
  # alias_method :notifications_thread, :issue
  def notifications_thread
    issue
  end

  def notify_socket_subscribers
    data = {
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "pull request review comment ##{id} updated",
        gid: global_relay_id,
    }
    channel = GitHub::WebSocket::Channels.pull_request_timeline(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel, data)
  end

  def build_reply(review:, body:, user: review.user)
    self.class.new(
      body: body,
      user: user,
      pull_request: pull_request,
      pull_request_review: review,
      pull_request_review_thread: pull_request_review_thread,
      reply_to_id: id
    )
  end

  # Override Referrer#track_references_in_background? so that references
  # are created in a background job.
  def track_references_in_background?
    true
  end

  # Public: Checks spamminess of associated pull request or pull request review.
  #
  # Returns a Boolean.
  def belongs_to_spammy_content?
    pull_request&.spammy? || pull_request_review&.spammy?
  end

  delegate *POSITIONING_ATTRS, to: :loaded_pull_request_review_thread, allow_nil: true
  delegate *POSITIONING_ATTRS.map { |attr| "#{attr}=" }, to: :loaded_pull_request_review_thread
  delegate *POSITIONING_ATTRS.map { |attr| "#{attr}_was" }, to: :loaded_pull_request_review_thread
  ############################################################################
  # WARNING: If removing these delegates, PLEASE ping the migration-tools
  # team @github/migration-tools-reviewers as this will cause breaking changes
  # and will require code updates to the migration importer for review comments.
  # Thank you in advance <3
  # - @github/migration-tools-reviewers
  ############################################################################
  DELEGATES_TO_REMOVE = %i(
    outdated?
    selection_contains_deletions?
    original_start_line
    original_line
    side
    original_selection
    excerpt
    excerpt_html
    start_line_number
    start_side
    line
    safe_line
    diff_hunk_lines
    original_pull_request_comparison
    live?
    diff_entry
    current_line
    current_line_range
    start_position_data
    end_position_data
    start_position_data=
    end_position_data=
  )
  delegate *DELEGATES_TO_REMOVE, to: :loaded_pull_request_review_thread
  delegate :on_line?, :on_file?, to: :loaded_pull_request_review_thread, allow_nil: true

  ASYNC_DELEGATES = %w[
    async_adjusted_blob_position
    async_adjusted_start_blob_position
    async_commit
    async_current_line
    async_end_line
    async_line
    async_safe_line
    async_original_commit
    async_original_diff
    async_original_line
    async_original_pull_request_comparison
    async_original_start_line
    async_selection_contains_deletions
    async_start_line
    async_start_line_number
    async_start_side
  ].index_with(&:itself)

  # All of these are stored on the PullRequestThread so we need an async-safe way to retrieve them.
  ASYNC_POSITIONING_DELEGATES = POSITIONING_ATTRS.index_with { |attr| "async_#{attr}" }

  ASYNC_DELEGATES.merge(ASYNC_POSITIONING_DELEGATES).each do |remote_name, local_name|
    define_method(local_name) do |*args, **kwargs, &block|
      T.unsafe(self).memoized_async_pull_request_review_thread.then do |thread|
        begin
          thread.public_send(remote_name, *args, **kwargs, &block) # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
        rescue NoMethodError
          if thread.nil?
            raise Module::DelegationError,
              "#{local_name} delegated to pull_request_review_thread.#{remote_name} async, but thread resolved to nil"
          else
            raise
          end
        end
      end
    end
  end

  def memoized_async_pull_request_review_thread
    @memoized_async_pull_request_review_thread ||= async_pull_request_review_thread
  end

  def comment_outside_diff_enabled?
    return @comment_outside_diff_enabled if defined?(@comment_outside_diff_enabled)
    @comment_outside_diff_enabled = GitHub.flipper[:comment_outside_the_diff].enabled?(repository)
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the safe_user which we know exists.
  def modifying_user
    @modifying_user ||= (User.find_by(id: GitHub.context[:actor_id]) || safe_user)
  end

  # This method simply calls the private `trigger_platform_subscriptions` method,
  # and has been added to support the CreateNewPullRequestReviewCommentOrchestration.
  # Since the `transaction_include_any_action` method called is also private,
  # extracting it into the orchestration is difficult. Additionally, since the
  # pull request review model also shares a private method by the
  # `trigger_platform_subscriptions` name, it seems that simply making the method
  # public would violate a design pattern. Hence this public 'alias'
  def public_trigger_platform_subscriptions
    trigger_platform_subscriptions
  end

  # This method has been changed from public to private to supoprt the
  # CreateNewPullRequestReviewCommentOrchestration. Given that other `subscribe_`
  # methods are similarly public and the only other `subsribe_to_issue` method
  # defined in the codebase appears to be on the issue_comment model,
  # there does not seem to be a significant reason or amount of prior art to
  # justify keeping it private
  def subscribe_to_issue
    subscribe(user, :comment)
  end

  # Making this public to support making PullRequestReviewCommentOrchestrations
  # the default codepaths for comment creation and deletion in the pull requests
  # AoR
  def loaded_pull_request_review_thread
    async_pull_request_review_thread.sync
  end

  protected

  def ensure_state_is_set
    self.state = :pending if state.blank?
  end

  def validate_review_is_pending
    return if (review = pull_request_review).nil? || review.pending?
    errors.add(:pull_request_review_id, "must be pending")
  end

  def validate_reply_relations
    return unless reply?
    return if (review_thread = pull_request_review_thread).nil?
    return unless review_thread.pull_request_review

    return if review_thread.published?

    same_author = user_id == review_thread.pull_request_review&.user_id
    return if same_author

    messages = []
    messages << "must be published" unless review_thread.published?
    messages << "must have review with same author as comment" unless same_author

    errors.add(:pull_request_review_thread_id, messages.join(" or "))
  end

  # Internal: overrides the Referrer to be the issue.
  alias_method :referrer, :issue

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns Newsies::Response instance.
  def get_notification_summary
    return unless issue
    list = Newsies::List.new("Repository", repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, issue)
  end

  def event_payload
    {
      comment: self,
      spammy: spammy?,
      submitted: submitted?,
      pull_request: pull_request&.id,
      repo: pull_request&.repository&.name_with_display_owner,
      allowed: allowed?,
      body: body,
      business: pull_request&.repository&.business,
      org: pull_request&.repository&.organization,
    }
  end

  def instrument_failed_validation
    instrument :validation_failed
  end

  # This has been made public to support the CreateNewPullRequestReviewCommentOrchestration.
  # Given that there is no definite pattern apparent between what methods are public
  # or private when it comes to instrumentation, there doesn't seem to be an explicit need
  # to keep this method protected.
  public def instrument_creation
    instrument :create

    GlobalInstrumenter.instrument("pull_request_review_comment.create", {
      actor: user,
      pull_request: pull_request,
      issue: issue,
      pull_request_creator: pull_request&.user,
      repository: repository,
      repository_owner: repository&.owner,
      pull_request_review: pull_request_review,
      review_comment: self,
      pull_request_review_thread: pull_request_review_thread,
    })
  end

  public def instrument_submission
    instrument :submission
  end

  def instrument_update
    payload = {
      actor: user_content_edits.last.try(:editor) || modifying_user,
      changes: {
        old_body: previous_changes[:body].try(:first),
        body: body
      }
    }
    instrument :update, payload

    GlobalInstrumenter.instrument("pull_request_review_comment.update", {
      actor: user,
      pull_request: pull_request,
      pull_request_creator: pull_request&.user,
      repository: repository,
      repository_owner: repository&.owner,
      review_comment: self,
      pull_request_review: pull_request_review,
      issue: pull_request&.issue,
    })
  end

  def instrument_deletion
    # If the destruction is happening as part of repo archiving
    # then there will be a lot of nil references during the destruction
    # and there will be no useful instrumentation data to store.
    return if repository.nil? || pull_request.nil?

    instrument :delete, repo: repository, actor: modifying_user, author: user

    GlobalInstrumenter.instrument("pull_request_review_comment.delete", {
      actor: user,
      pull_request: pull_request,
      repository: repository,
      review_comment: self,
      pull_request_review: pull_request_review,
      pull_request_review_thread: pull_request_review_thread,
    })
  end

  # Private: initially overwriting the 'body_changed_after_commit?' active record
  # method as it does not appear to recognize Japanese (and likely other) characters
  # as the same characters when read from its body column against the previous 'body'
  # characters when 'save!' is called.

  # see: https://github.com/github/pull-requests/issues/9823 for more informaiton
  private def body_changed_after_commit?
    return false if utf8(previous_changes[:body].try(:first)) == body

    super
  end

  private def clean_up_review
    return unless review = pull_request_review
    review.destroy_if_empty
  end

  # Internal: Destroy review thread if there are no other associated comments.
  private def clean_up_review_thread
    return unless review_thread = pull_request_review_thread
    review_thread.destroy_if_empty
  end

  private def clean_up_review_and_review_thread
    clean_up_review_thread
    clean_up_review
  end

  # Private: Should we send deletion webhooks?
  private def send_deleted_webhook?
    if spammy? || pending?
      false
    else
      true
    end
  end

  # Private: Serializes this PullRequestReviewComment as a webhook payload for any apps
  # that listen for Hook::Event::PullRequestReviewCommentEvents. Under normal circumstances
  # we deliver webhook events using instrumentation, but this must be called as
  # a before_destroy and uses Hook::Event#generate_payload_and_deliver_later to
  # serialize the webhook payload before the record becomes unavailable.
  #
  # Returns nothing.
  def generate_webhook_payload
    if modifying_user&.spammy?
      @delivery_system = nil
      return
    end

    event = Hook::Event::PullRequestReviewCommentEvent.new(action: :deleted, pull_request_review_comment_id: id, actor_id: modifying_user.id, triggered_at: Time.now)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_webhook_delivery
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload' must be called before `queue_webhook_delivery'"
    end

    @delivery_system&.deliver_later
  end

  def generate_issue_event
    if issue && modifying_user != user
      issue.events.create \
        event: "comment_deleted",
        actor: modifying_user,
        subject: user
    end
  end

  def code_scanning_variant_body_cannot_be_edited
    body_before, body_after = body_change

    # This validation method is only called when there is a change detected in the body.
    # But that doesn't necessarily mean that the body was changed. Reasons:
    # * The body method is overridden and can return a string value with a different encoding than the value from the
    #   database, thus making it seem like the body was changed.
    # * The `unicode` validation on the body can also result in the body encoding being changed.
    return true if utf8(body_before) == utf8(body_after)

    if code_scanning?
      errors.add(:body, "is not editable")
      return false
    end

    true
  end

  def validate_can_be_deleted
    # If the associated pull request has been destroyed, then this comment
    # is almost certainly being destroyed as part of a dependent destroy,
    # and we should allow that.
    #
    # Reviews can't be deleted directly, but if one was, that would be
    # caught by the fact that `code_scanning?` returns false if
    # `async_pull_request_review` is nil.
    if code_scanning? && !pull_destroyed?
      errors.add(:base, "cannot be deleted")
      throw(:abort)
    end
  end

  # Validation to see if commenting is allowed based on pull request lock
  # Only someone allowed to push to the repository can comment on a locked pull request
  # (unlocked pull requsts have no such restriction)
  #
  # Returns true if comment is allowed, adds an error otherwise
  def validate_pull_request_lock
    pr = T.must(pull_request)
    return true unless pr.issue&.locked?
    return true if pr.repository&.pushable_by?(user)

    errors.add(:base, "lock prevents comment")
  end

  def ensure_creator_is_not_blocked
    return unless user && (pr = pull_request)

    if pr.blocked_from_reviewing?(user)
      errors.add(:user, "is blocked")
    end
  end

  def assign_repository_from_pull_request
    self.repository = pull_request.try(:repository)
  end

  def validate_authorized_to_create_content
    operation = new_record? ? :create : :update
    authorization = ContentAuthorizer.authorize(modifying_user, :pull_request_comment, operation,
                                                issue: issue,
                                                repo: repository)

    if authorization.failed?
      errors.add(:base, authorization.error_messages)
    end
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_pull_request_review_comment_id
  end

  private

  def touch_pull_request_after_commit
    return unless legacy_comment?
    pull_request&.touch
  end

  # Private: Update the `update_pull_request_counters` attr on `PullRequest` model
  def update_pull_request_counters
    return unless legacy_comment?
    return unless (pr = pull_request)

    pr.update_review_comments_count
  end

  def trigger_platform_subscriptions
    return if (pr = pull_request).nil?

    # trigger when the comment is submitted or deleted
    if previous_changes.include?(:state) || transaction_include_any_action?([:destroy])
      actor = User.find_by(id: GitHub.context[:actor_id])
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
        Platform::Schema.subscriptions.trigger(
          :pull_request_comments_updated,
          { id: pr.global_relay_id }
        )
      end
    end
  end

  def reparent_replies
    GitHub.dogstats.time("pull_request_review_comment", tags: ["action:reparent_replies"]) do
      new_parent_id = self.class.connection.select_value(Arel.sql(<<-SQL, pull_request_id: pull_request_id, reply_to_id: id))
        SELECT id FROM pull_request_review_comments
        WHERE pull_request_id = :pull_request_id AND reply_to_id = :reply_to_id
        ORDER BY created_at
      LIMIT 1
      SQL

      return unless new_parent_id

      self.class.connection.update(Arel.sql(<<-SQL, new_parent_id: new_parent_id, pull_request_id: pull_request_id, reply_to_id: id))
        UPDATE pull_request_review_comments
        SET reply_to_id = :new_parent_id
        WHERE pull_request_id = :pull_request_id AND reply_to_id = :reply_to_id AND id != :reply_to_id
      SQL

      self.class.connection.update(Arel.sql(<<-SQL, id: new_parent_id))
        UPDATE pull_request_review_comments
        SET reply_to_id = NULL
        WHERE id = :id
      SQL
    end
  end

  # Override GitHub::UserContent#attach_matching_assets? so that we only
  # attempt to attach matching assets when the review comment's body changes.
  def attach_matching_assets?
    body_previously_changed?
  end

  # Only track references when the review is submitted
  def track_references?
    submitted?
  end

  def blob_failure_context
    {
      blob_commit_oid: loaded_pull_request_review_thread.blob_commit_oid,
      blob_position:   loaded_pull_request_review_thread.blob_position,
      blob_path:       loaded_pull_request_review_thread.blob_path,
      app:             "github-blob-positioning",
    }
  end

  def unresolve_thread_if_not_conversation
    return unless review_thread  = pull_request_review_thread

    if review_thread.resolved? & !review_thread.conversation?
      review_thread.unresolve(unresolver: Apps::Internal.integration(:code_scanning).bot)
    end
  end

  def target_for_conditional_access
    return unless repo = repository
    repo.target_for_conditional_access
  end

  def saved_reply_copy_target
    self.repository
  end
end
