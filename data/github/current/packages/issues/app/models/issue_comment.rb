# typed: true
# frozen_string_literal: true

class IssueComment < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include GitHub::Relay::GlobalIdentification
  include EmailReceivable
  include NotificationsContent::WithCallbacks
  include Instrumentation::Model
  include Referrer
  include Reaction::Subject::RepositoryContext
  include Spam::Spammable
  include UserContentEditable
  include InteractionBanValidation
  include AuthorAssociable
  include GitHub::MinimizeComment
  include OrgBlockable
  include AbuseReportable
  include TemplatableContent
  include LegacyImportable
  include Reactable
  include PreloadableAttributes
  include SlashCommands::EmbeddedCommands
  include GitHub::Memoizer
  include Storage::UserAssetTransfer::SavedReplyCopyDependency
  extend GitHub::CallbackInstrumenter

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::IssueComment

  belongs_to :user
  belongs_to :repository

  def entity = repository
  def async_entity = async_repository

  alias_attribute :body, :compressed_body
  belongs_to :issue
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration,
    foreign_key: :performed_by_integration_id,
    class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  has_many :reactions, class_name: "IssueCommentReaction"
  T.unsafe(self).destroy_dependents_in_background :reactions, sharding_key: :repository_id, sharding_value_key: :repository_id

  # remove this once double-writing reactions gets removed. This is only here for destroy_dependents_in_background.
  has_many :legacy_reactions, class_name: "Reaction", as: :subject
  T.unsafe(self).destroy_dependents_in_background :legacy_reactions

  setup_spammable(:user)

  before_validation :assign_repository_from_issue, on: :create

  validates_presence_of :issue_id
  validates_presence_of :body, message: "cannot be blank"
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true
  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :ensure_issue_not_converted_to_discussion

  setup_attachments
  T.unsafe(self).setup_referrer

  attribute :compressed_body, CompressedBinary.new(self.name, "body")

  attr_accessor :issue_transfer

  # Whether or not to create the CreateIssueCommentOrchestration manually
  attr_accessor :skip_create_issue_comment_orchestration

  after_create :initialize_create_issue_comment_orchestration # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  attr_preloadable :viewer_can_update, :viewer_can_react, :viewer_can_read_user_content_edits,
                   :body_html,
                   :readable_by, :viewer_can_minimize, :user_is_spammy,
                   :reaction_groups, :reaction_path,
                   :report_count, :top_report_reason, :last_reported_at, :author_association_symbol

  after_commit :update_issue_comments_count, on: [:create, :destroy], unless: -> { T.bind(self, IssueComment); issue_transfer? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_destroy :generate_webhook_payload, unless: :spammy? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :trigger_graphql_subscription, unless: :spammy?, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_destroy :generate_issue_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :queue_webhook_delivery, unless: :spammy?, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_update, on: :update, if: -> { T.bind(self, IssueComment); !issue_transfer? && body_changed_after_commit? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # spam check on create handled by Newsies::DeliverNotificationsJob
  after_commit :enqueue_check_for_spam, on: :update,  if: :check_for_spam? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :synchronize_search_index, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_issue_summary_socket_subscribers, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :trigger_graphql_timeline_subscriptions, on: :create, unless: -> { T.bind(self, IssueComment); importing? || issue_transfer? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_subscriptions_and_notify, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :process_slash_commands, on: :create, if: :should_process_slash_commands? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :attach_matching_assets, if: :attach_matching_assets_on_update_after_commit?, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :touch_issue, on: [:update, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :execute_create_issue_comment_orchestration # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validate :validate_comment_is_authorized, unless: -> { T.bind(self, IssueComment); importing? || issue_transfer? }
  validate :ensure_creator_is_not_blocked, unless: -> { T.bind(self, IssueComment); comment_hidden_changed? || issue_transfer? }

  scope :since, -> (time) {
    where("issue_comments.updated_at >= ?", time)
  }

  scope :sorted_by, -> (order_str, direction) {
    opts = { order: "issue_comments.created_at DESC" }

    if !order_str.blank?
      case order_str
      when /created/
        opts[:order] = "issue_comments.created_at"
      when /updated/
        opts[:order] = "issue_comments.updated_at"
      else
        opts[:order] = "issue_comments.created_at"
      end

      opts[:order] += (direction == "asc" ? " ASC" : " DESC")
    end

    order(opts[:order])
  }

  scope :with_issue, -> { joins(:issue) }

  scope :with_pull_request,    -> { joins(:issue).where("issues.pull_request_id IS NOT NULL") }
  scope :without_pull_request, -> { joins(:issue).where("issues.pull_request_id IS NULL") }

  enum :comment_hidden_by, GitHub::MinimizeComment::ROLES

  def issue_transfer?
    defined?(issue_transfer) && issue_transfer == true
  end

  # Disable the default behavior of attaching assets in `after_save` defined in `setup_attachments`.
  # We want to call it outside of the transaction in `after_commit` instead.
  def attach_matching_assets?
    false
  end

  def attach_matching_assets_on_update_after_commit?
    true unless issue_transfer?
  end

  def track_references_in_background?
    true
  end

  def notifications_author
    user
  end

  def notifications_thread
    issue
  end

  def async_notifications_list
    async_repository
  end

  def compressed_body
    utf8(read_attribute(:compressed_body))
  end
  alias_method :body, :compressed_body

  # For quickly fixing those users that have not mastered pasting code into markdown
  def make_pre_block
    update_attribute(:body, body.gsub(/^(.+)$/, '    \1'))
  end

  def readable_by?(user)
    return @readable_by if defined? @readable_by

    async_readable_by?(user).sync
  end

  def async_readable_by?(user)
    async_issue.then do |issue|
      next false unless issue
      issue.async_readable_by?(user)
    end
  end

  def async_writable_by?(viewer, repo)
    repo.async_writable_by?(viewer)
  end

  def async_viewer_can_create_issue?(viewer, repo)
    return Promise.resolve(false) unless repo && viewer

    Promise.all([async_writable_by?(viewer, repo), repo.async_preferred_issue_templates]).then do |writable, templates|
      config = templates.issue_template_config
      writable || config.blank_issues_enabled?
    end
  end

  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    async_viewer_cannot_delete_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_delete_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([async_issue, async_repository, async_user]).then do |issue, repository, _user|
      Promise.all([issue.async_pull_request, issue.async_repository, repository.async_owner]).then do
        context = { repo: repository, issue: issue }
        errors = ContentAuthorizer.authorize(viewer, :IssueComment, :delete, context).errors.map(&:symbolic_error_code)

        async_deletable_by?(viewer).then do |deletable_by_viewer|
          errors << :insufficient_access unless deletable_by_viewer
          errors
        end
      end
    end
  end

  def async_deletable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_repository.then do |repository|
      next false unless repository

      async_user.then do |user|
        # Deleting comments made by ghost users is allowed, but not editing
        user ||= User.ghost
        next true if user == viewer

        repository.async_writable_by?(viewer)
      end
    end
  end

  def async_viewer_can_update?(viewer)
    return Promise.resolve(false) if viewer.nil?

    current_query_info = Platform::GlobalScope.queries.last
    variables = current_query_info[:variables] unless current_query_info.nil?
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([async_issue, async_repository, async_user]).then do |issue, repository, _user|
      Promise.all([issue.async_pull_request, issue.async_repository, repository.async_owner, viewer.async_enterprise_managed_business]).then do
        context = { repo: repository, issue: issue }
        errors = ContentAuthorizer.authorize(viewer, :IssueComment, :edit, context).errors.map(&:symbolic_error_code)

        async_editable_by?(viewer).then do |editable_by_viewer|
          errors << :insufficient_access unless editable_by_viewer
          errors
        end
      end
    end
  end

  # TODO: The logic in this method should probably be moved into the `ContentAuthorizer` framework,
  #       but that is not async-aware yet, so this is the best place for this right now.
  #
  #       See `PullRequestReviewComment#async_editable_by?` for a similar check on `PullRequestReviewComment`s.
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

  def async_minimizable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(true) if actor.site_admin?

    # Users can always minimize their own comments, unless they're restricted
    # by internal App policy...
    return Promise.resolve(true) if unrestricted_actor_minimizing_own_comment?(actor)

    Promise.all([async_issue, async_repository]).then do |issue, repository|
      next false unless repository

      issue.async_pull_request.then do |pull|
        is_writable_promise = if pull.present?
          repository.resources.pull_requests.async_writable_by?(actor)
        else
          repository.resources.issues.async_writable_by?(actor)
        end

        is_writable_promise.then do |is_writable|
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
  end

  # Public: Get the Sponsorship from the comment author to the repository owner.
  #
  # viewer - User loading the comment.
  #
  # Returns a Promise<Sponsorship> or a Promise<nil>.
  def async_author_to_repo_owner_sponsorship(viewer)
    async_repository.then do |repo|
      next unless repo
      repo.async_owner_sponsorship_from(T.unsafe(user_id), viewer: viewer)
    end
  end

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

  def stafftools_url
    "/stafftools/repositories/#{T.must(repository).nwo}/issues/#{T.must(issue).number}/comments/#{id}"
  end

  # Absolute permalink URL for this issue comment.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                issue_comment.permalink(include_host: false) => `/github/github/issue/1#issuecomment-2`
  #
  def permalink(include_host: true)
    "#{T.must(issue).permalink(include_host: include_host)}##{anchor}"
  end
  alias url permalink

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_issue.then { |x| T.must(x).async_path_uri }.then do |path_uri|
      path_uri = path_uri.dup
      path_uri.fragment = anchor
      path_uri
    end
  end

  def anchor
    "issuecomment-#{id}"
  end

  # Unique identifier for this issue comment. Used in email messages.
  def message_id
    "<#{T.must(repository).name_with_display_owner}/issues/#{T.must(issue).number}/#{id}@#{GitHub.urls.host_name}>"
  end

  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  def safe_user
    user || User.ghost
  end

  def subscribe_mentioned(mentions = mentioned_users, author = user)
    T.must(issue).subscribe_mentioned(mentions, author)
  end

  def trigger_graphql_subscription
    return unless issue = self.issue

    Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { deleted_comment_id: global_relay_id })
  end

  def notify_graphql_subscribers
    return unless issue = self.issue

    unless issue.pull_request?
      Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { reacted_comment_id: global_relay_id })
    end
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo.  Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of Users that can be unsubscribed.
  def unsubscribable_users(users)
    T.must(issue).unsubscribable_users(users)
  end

  # See IssueTimeline
  def timeline_sort_by
    [created_at]
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the safe_user which we know exists.
  def modifying_user
    is_staff_action = GitHub.context[:from]&.include?("stafftools") || GitHub.context[:staff_actor]
    if is_staff_action && GitHub.guard_audit_log_staff_actor?
      @modifying_user = User.staff_user
    else
      @modifying_user ||= (User.find_by(id: GitHub.context[:actor_id]) || safe_user)
    end
    @modifying_user
  end

  def last_modified_at
    @last_modified_at ||= T.unsafe(self).last_modified_with :user
  end

  # Collect conditions under which we don't bother checking the content
  # of this Issue for spam.
  def skip_spam_check?
    repository = T.must(self.repository)
    user = T.unsafe(self.user)

    !GitHub.flipper[:issue_comments_spam_check].enabled? ||   # IssueComment spam checks now turned off in production
    repository.private?      ||   # Leave private repos alone.
    repository.member?(user) ||   # Don't bother repo members.
    user.nil?                ||
    !user.can_be_flagged?    ||   # No point in checking these,
    user.spammy?                  # since nothing will change.
  end

  def check_for_spam?
    persisted? && !skip_spam_check?
  end

  # Public: Checks spamminess of associated issue.
  #
  # Returns a Boolean.
  def belongs_to_spammy_content?
    issue&.spammy?
  end

  # Check the comment for spam
  #
  # options - currently unused
  def check_for_spam(options = {})
    return if skip_spam_check?

    user = T.must(self.user)

    if reason = GitHub::SpamChecker.test_comment(self)
      base_msg = "IssueComment spam (%s): %s" % [permalink, reason]

      if !user.can_be_flagged?
        GitHub::SpamChecker.notify("Regular checks said [%s], but user %s (%d) is NEVER SPAMMY." %
                                     [base_msg, user.login, user.id])
      elsif GitHub::SpamChecker.fairly_active?(user)
        GlobalInstrumenter.instrument(
          "add_account_to_spamurai_queue",
          {
            account_global_relay_id: user.global_relay_id,
            additional_context: "RESQUE_CHECK_FOR_SPAM_ISSUE_COMMENT",
            origin: :RESQUE_CHECK_FOR_SPAM_ISSUE_COMMENT,
            queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
          },
        )
        GitHub.dogstats.increment("spam.active_user_review")
        GitHub::SpamChecker.notify("[%s], but user %s (%d) seems fairly active, so queuing for review." %
                                     [base_msg, user.login, user.id])
      else
        user.safer_mark_as_spammy(reason: base_msg)
        GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:issue_comment"]
      end
    end
  end

  # Public: Issues mentioned in the body as being a duplicate of this one.
  #
  # The GitHub::HTML::IssueMentionFilter must be part of the body pipeline for this
  # information to be extracted.
  #
  # Returns an array of Issue objects.
  def duplicate_issues
    Array(body_result.issues).select { |ref| ref.duplicate? }.map(&:issue).uniq
  end

  def notify_socket_subscribers
    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "issue comment ##{id} updated",
      gid: global_relay_id,
    }

    issue = T.must(self.issue)

    if issue.pull_request?
      channel = GitHub::WebSocket::Channels.pull_request_timeline(issue.pull_request)
      GitHub::WebSocket.notify_pull_request_channel(issue.pull_request, channel, data)
    else
      channel = GitHub::WebSocket::Channels.issue_timeline(issue)
      GitHub::WebSocket.notify_issue_channel(issue, channel, data)
      if body_changed_after_commit?
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { comment_updated_id: global_relay_id })
      end
    end
  end

  sig { returns(T.untyped) }
  def notify_issue_summary_socket_subscribers
    channel = GitHub::WebSocket::Channels.issue_summary(issue)

    GitHub::WebSocket.notify_issue_channel(issue, channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "issue comment ##{id} updated",
      gid: global_relay_id,
    )
  end

  def trigger_graphql_timeline_subscriptions
    issue = T.must(self.issue)

    unless issue.pull_request?
      Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { issue_timeline_updated: true })
    end
  end

  def preload_viewer_attributes(viewer, repo)
    viewer_data = Promise.all(
     [
       async_viewer_can_delete?(viewer),
       async_viewer_can_update?(viewer),
       async_viewer_cannot_update_reasons(viewer),
       async_viewer_can_report?(viewer),
       async_viewer_can_report_to_maintainer?(viewer),
       async_minimizable_by?(viewer),
       async_unminimizable_by?(viewer),
       async_viewer_can_block_from_org?(viewer),
       async_viewer_can_unblock_from_org?(viewer),
       async_viewer_relationship(viewer),
       async_viewer_can_create_issue?(viewer, repo)
     ]
   ).sync

    @viewer_can_delete,
    @viewer_can_update,
    @viewer_cannot_update_reasons,
    @viewer_can_report,
    @viewer_can_report_to_maintainer,
    @viewer_can_minimize,
    @viewer_can_unminimize,
    @viewer_can_block_from_org,
    @viewer_can_unblock_from_org,
    @viewer_relationship,
    @viewer_can_create_issue = viewer_data
  end

  def viewer_can_delete?(user = nil)
    return async_viewer_can_delete?(user).sync unless user.nil?
    return @viewer_can_delete if defined?(@viewer_can_delete)
    false
  end

  def viewer_can_update?(user = nil)
    # this does not support multiple viewers currently
    if defined? @viewer_can_update
      return @viewer_can_update
    end

    if user.nil?
      return false
    end

    @viewer_can_update = async_viewer_can_update?(user).sync
    @viewer_can_update
  end

  def viewer_cannot_update_reasons(user = nil)
    if user.nil?
      if defined? @viewer_cannot_update_reasons
        return @viewer_cannot_update_reasons
      else
        return false
      end
    end
    async_viewer_cannot_update_reasons(user).sync
  end

  def viewer_can_report(user = nil)
    if user.nil?
      if defined? @viewer_can_report
        return @viewer_can_report
      else
        return false
      end
    end
    async_viewer_can_report?(user).sync
  end

  def viewer_can_report_to_maintainer(user = nil)
    if user.nil?
      if defined? @viewer_can_report_to_maintainer
        return @viewer_can_report_to_maintainer
      else
        return false
      end
    end
    async_viewer_can_report_to_maintainer?(user).sync
  end

  def viewer_can_minimize?(user = nil)
    # does not support multiple users
    if defined? @viewer_can_minimize
      return @viewer_can_minimize
    end

    if user.nil?
      return false
    end

    async_minimizable_by?(user).sync
  end

  def viewer_can_unminimize?(user = nil)
    if user.nil?
      if defined? @viewer_can_unminimize
        return @viewer_can_unminimize
      else
        return false
      end
    end
    async_unminimizable_by?(user).sync
  end

  def viewer_can_block_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_block_from_org
        return @viewer_can_block_from_org
      else
        return false
      end
    end
    async_viewer_can_block_from_org?(user).sync
  end

  def viewer_can_unblock_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_unblock_from_org
        return @viewer_can_unblock_from_org
      else
        return false
      end
    end
    async_viewer_can_unblock_from_org?(user).sync
  end

  def viewer_relationship(user = nil)
    if user.nil?
      if defined? @viewer_relationship
        return @viewer_relationship
      else
        return false
      end
    end

    async_viewer_relationship(user).sync
  end

  def viewer_can_create_issue?(viewer = nil, repo = nil)
    if viewer.nil? && repo.nil?
      if defined? @viewer_can_create_issue
        return @viewer_can_create_issue
      else
        return false
      end
    end
    T.unsafe(self).async_viewer_can_create_issue(viewer, repo).sync
  end

  # see NotificationsContent
  def deliver_notifications?
    !importing?
  end

  def instrument_creation
    instrument :create

    GlobalInstrumenter.instrument "issue_comment.create", {
      actor: user,
      issue: issue,
      issue_creator: T.must(issue).user,
      issue_comment: self,
      repository: repository,
      repository_owner: T.must(repository).owner,
    }
  end

  def touch_issue
    # if previous_changes is not empty it means the issue was already updated in the same transaction
    issue&.touch if issue&.previous_changes&.empty?
  end

  private

  def update_issue_comments_count
    return unless issue = self.issue

    issue.without_update_issue_orchestration do
      issue.update_issue_comments_count
    end
  end

  def validate_comment_is_authorized
    operation = new_record? ? :create : :update
    authorization = ContentAuthorizer.authorize(modifying_user, :issue_comment, operation,
                                                repo: repository,
                                                issue: issue)

    if authorization.failed?
      errors.add(:base, authorization.error_messages)
    end
  end

  def ensure_creator_is_not_blocked
    return unless user = self.user
    return unless issue = self.issue
    return true if issue.repository&.pushable_by?(user)

    if user.blocked_by?([issue.repository&.owner, issue.user])
      errors.add(:user, "is blocked")
    end
  end

  # Internal: overrides the Referrer to be the issue.
  def referrer = issue

  def assign_repository_from_issue
    self.repository = issue.try(:repository)
  end

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns Newsies::Response instance.
  def get_notification_summary
    if issue
      list = Newsies::List.new("Repository", repository_id)
      GitHub.newsies.web.find_rollup_summary_by_thread(list, issue)
    end
  end

  def event_payload
    payload = {
      repo:          repository,
      issue:         issue,
      issue_comment: self,
      spammy:        T.unsafe(self).spammy?,
      body:          body,
      allowed:       allowed?,
    }

    if repository.try(:in_organization?)
      payload[:org] = T.must(repository).organization
    end

    payload
  end

  def allowed?
    repository.permit?(user, :write)
  end

  def instrument_update
    previous_body = body_previously_was
    instrument :update, old_body: previous_body, private_repo: T.must(repository).private?

    GlobalInstrumenter.instrument "issue_comment.update", {
      actor: user,
      issue: issue,
      issue_creator: T.must(issue).user,
      issue_comment: self,
      previous_body: previous_body,
      repository: repository,
      repository_owner: T.must(repository).owner,
    }
  end

  def instrument_destruction
    return unless user = self.user

    instrument :destroy,
      author_id:  user.id,
      author: user.display_login
  end

  # Was the comment body changed in previous_changes? We use this to determine
  # if body changes _only_ after_commit.
  def body_changed_after_commit?
    body_previously_changed?
  end

  # Tell the owning issue to kick off a search index update
  def synchronize_search_index
    T.must(issue).synchronize_search_index
  end

  # Private: Serializes this IssueComment as a webhook payload for any apps
  # that listen for Hook::Event::IssueCommentEvents. Under normal circumstances
  # we deliver webhook events using instrumentation, but this must be called as
  # a before_destroy and uses Hook::Event#generate_payload_and_deliver_later to
  # serialize the webhook payload before the record becomes unavailable.
  def generate_webhook_payload
    if modifying_user&.spammy?
      @delivery_system = nil
      return
    end

    triggered_at = Time.now
    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)
    @deleted_tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(issue_comment: self, guid: event_guid)

    event = Hook::Event::IssueCommentEvent.new issue_comment_id: self.id, action: :deleted, triggered_at: triggered_at, event_guid: event_guid
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def generate_issue_event
    if issue && modifying_user != user
      T.must(issue).events.create \
        event: "comment_deleted",
        actor: modifying_user,
        subject: user
    end
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_webhook_delivery
    raise "`generate_webhook_payload' must be called before `queue_webhook_delivery'" unless defined?(@delivery_system)

    # This is temporary until we migrate the issue comment deleted event to use the new staffshipping flags.
    # https://github.com/github/ecosystem-events/issues/4916
    event_flags = Events::Tier1EventPublisher::EventFlags.new(
      webhook_deliveries_enabled: false,
      hookshot_deliveries_enabled: true,
      events_v2_validation_enabled: false,
      publish_tier1_events: true,
    )
    Events::IssueCommentPublisher.publish(tier1_event: @deleted_tier1_event, event_flags: event_flags) if @deleted_tier1_event

    @delivery_system&.deliver_later
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_issue_comment_id
  end

  def ensure_issue_not_converted_to_discussion
    return unless issue = self.issue
    return unless repository = self.repository
    return unless repository.discussions_active?

    if issue.discussion
      errors.add(:base, "Cannot be modified since the issue has been converted to a discussion.")
    end
  end

  def initialize_create_issue_comment_orchestration
    return if skip_create_issue_comment_orchestration

    @create_issue_comment_orchestration = IssueCommentOrchestration.create_issue_comment!(
      actor: modifying_user,
      comment: self
    )

    @create_issue_comment_orchestration.log_info("Created IssueComment orchestration")
  end

  def execute_create_issue_comment_orchestration(synchronous: false)
    return if @create_issue_comment_orchestration.nil?
    return if skip_create_issue_comment_orchestration

    o = @create_issue_comment_orchestration
    @create_issue_comment_orchestration = nil

    o.log_info("Execute IssueComment orchestration")

    o.execute synchronous: synchronous
  end

  def saved_reply_copy_target
    self.repository
  end
end
