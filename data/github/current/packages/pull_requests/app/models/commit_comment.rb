# typed: true
# frozen_string_literal: true

class CommitComment < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::UTF8
  include GitHub::UserContent
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include EmailReceivable
  include NotificationsContent::WithCallbacks
  include Reaction::Subject::RepositoryContext
  include Instrumentation::Model
  include Spam::Spammable
  include UserContentEditable
  include GitHub::Relay::GlobalIdentification
  include InteractionBanValidation
  include AuthorAssociable
  include GitHub::MinimizeComment
  include OrgBlockable
  include AbuseReportable
  include Reactable
  include PreloadableAttributes
  include LegacyImportable
  include LastModifiedCalculation

  attr_preloadable  :author_association_symbol

  belongs_to :user
  belongs_to :repository
  destroy_in_background_with :repository

  def entity
    repository
  end

  def async_entity
    async_repository
  end

  has_many :reactions, class_name: "CommitCommentReaction"

  setup_spammable(:user)

  validates_presence_of     :commit_id, :body
  validates_numericality_of :user_id, :repository_id
  validates_numericality_of :position, if: proc { |m| m.position.present? }
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true
  validate :commit_not_locked, unless: :importing?
  validate :validate_comment_is_authorized, unless: :importing?
  validate :ensure_creator_is_not_blocked, on: :create
  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?

  setup_attachments

  before_save   :clear_blank_path_line # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # spam check on create handled by Newsies::DeliverNotificationsJob
  after_commit :enqueue_check_for_spam, on: :update,  if: :check_for_spam? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_creation, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :subscribe_comment_participants # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_save :reference_mentioned_issues # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_update, on: :update, if: :body_changed_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_destruction, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :subscribe_and_notify,            on: :create, unless: :importing? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_subscriptions_and_notify, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :for_display, -> (viewer, commit, repository) {
    where(commit_id: commit.oid, repository_id: repository.id)
      .filter_spam_for(viewer)
      .order(:id)
  }

  scope :inline, -> { where("position IS NOT NULL") }
  scope :inline_only_paths, -> { where("position IS NOT NULL AND path IS NOT NULL") }

  scope :discussion, -> { where(position: nil) }

  # Return a new relation that "explicitly" joins a pull request
  # for each commit oid.
  #
  # commit_oids_by_pull_request_id - A hash containing lists of commit oids
  #                                  indexed by the pull request id they belong to.
  scope :with_pull_requests, ->(commit_oids_by_pull_request_id) {
    conditions = commit_oids_by_pull_request_id.map do |pull_request_id, commit_oids|
      sanitize_sql([
        "(`pull_requests`.`id` = ? AND `commit_comments`.`commit_id` IN (?))",
        pull_request_id,
        commit_oids,
      ])
    end.join(" OR ")

    # TODO: We have to tell MySQL to use the `index_commit_comments_on_commit_id` index.
    #       Without this hint, MySQL tends to use a different index, which causes it to
    #       scan through a large number of `commit_comments` rows to find the ones
    #       matching the given commit ids.
    #
    #       Because commit oids are almost unique across repos, forcing an index for the
    #       `commit_id` column speeds up the performance of this query considerably.
    #
    #       Long-term, we should look into adding an index that covers both the
    #       `commit_id` and `repository_id` columns and remove the index hint.
    from("#{self.table_name} USE INDEX(index_commit_comments_on_commit_id)").joins(<<~SQL)
      INNER JOIN `pull_requests` ON
        (`pull_requests`.`head_repository_id` = `commit_comments`.`repository_id` OR
          `pull_requests`.`base_repository_id` = `commit_comments`.`repository_id`
        ) AND (#{conditions})
    SQL
  }

  # Returns a new Relation that returns `CommitComment`s part of the given
  # commit comment threads.
  #
  # A thread key consists of `repository_id`, `commit_id`, `path` and `position`.
  scope :in_threads, -> (thread_keys) {
    conditions = thread_keys.map do |_, _, path, _|
      <<~SQL
        (
          `commit_comments`.`repository_id` = ? AND
          `commit_comments`.`commit_id` = ? AND
          (`commit_comments`.`path` <=> ?#{" OR `commit_comments`.`path` = ''" unless path}) AND
          `commit_comments`.`position` <=> ?
        )
      SQL
    end.join(" OR ")

    T.unsafe(self).where(conditions, *thread_keys.flatten)
  }

  # Possible CommentCommentThread parent association.
  # Caution: Will only be set if loaded from a CommentCommentThread finder.
  attr_accessor :thread

  enum :comment_hidden_by, GitHub::MinimizeComment::ROLES

  def self.find_for_position(position, path, viewer, commit, repository)
    commit_oid = commit.is_a?(String) ? commit : commit.oid
    repo_id = repository.is_a?(Repository) ? repository.id : repository

    filter_spam_for(viewer).where(
      repository_id: repo_id,
      commit_id: commit_oid,
      path: path,
      position: position,
    )
  end

  def self.find_for(viewer, commit, repository, only_paths = false)
    commit_oid = commit.is_a?(String) ? commit : commit.oid
    repo_id = repository.is_a?(Repository) ? repository.id : repository

    conditions = if only_paths
      ["repository_id = ? and commit_id = ? AND path IS NOT NULL", repo_id, commit_oid]
    else
      ["repository_id = ? and commit_id = ?", repo_id, commit_oid]
    end

    comments =
      filter_spam_for(viewer)
      .where(conditions)
      .order(id: :asc)
      .to_a

    comments.each do |comment|
      comment.commit = commit
      comment.repository = repository
    end

    comments
  end

  # Override reading the body to guarantee returning valid utf8 encoded data.
  #
  # See also GitHub::UTF8
  def body
    utf8(read_attribute(:body))
  end
  alias_method :to_s, :body
  # Public: A CommitComment can never be in a pending state.
  # See also PullRequestReviewComment#pending?
  #
  # Returns a Boolean
  def pending?
    false
  end

  # Public: Sets the path for the commit comment. Blank paths are treated
  # as `nil`.
  #
  # Returns the set path.
  def path=(value)
    write_attribute(:path, value.presence)
  end

  def path
    if attr = read_attribute(:path).presence
      attr.dup.force_encoding("UTF-8")
    end
  end

  def line_number
    line ?  "L#{line}" : ""
  end

  attr_writer :commit

  def commit
    @commit ||= repository&.commits.find(commit_id)
  rescue GitRPC::ObjectMissing
  end

  # Getting the url for the commit comment
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                issue_comment.permalink(include_host: false) => `/github/github/commit/sd0979`
  #
  def url(include_host: true)
    "#{repository&.permalink(include_host: include_host)}/commit/#{commit_id}"
  end
  alias_method :permalink, :url

  def stafftools_url
    "/stafftools/commit_comments/#{id}"
  end

  # There are two types of commit comments: inline comments and comments on
  # the commit as a whole. Inline comment dom IDs have a `#r{database_id}`
  # format while dom IDs for comments on the commit as a whole have a
  # `commitcomment-{database_id}` format. So, commit comment URLs
  # need to have the correct fragment format.
  def url_fragment
    inline? ? "r#{id}" : "commitcomment-#{id}"
  end

  # Public: Returns the permalink URL for the commit comment, including the
  # fragment.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                commit_comment.full_permalink(include_host: false) => `/github/github/commit/sd0979#commitcomment-7331`
  #
  # why doesn't #url or #permalink have the anchor?
  def full_permalink(include_host: true)
    "#{url(include_host: include_host)}##{url_fragment}"
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then do |repo|
      path_uri = T.must(repo).path_uri.dup
      path_uri.path += "/commit/#{commit_id}"
      path_uri.fragment = url_fragment
      path_uri
    end
  end

  def async_update_path_uri
    return @async_update_path_uri if defined?(@async_update_path_uri)

    @async_update_path_uri = async_repository.then do |repo|
      path_uri = T.must(repo).path_uri.dup
      path_uri.path += "/commit_comment/#{id}"
      path_uri
    end
  end

  def async_performed_via_integration
    Promise.resolve(nil)
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def async_editable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_repository.then do |repository|
      next false unless repository

      Promise.all([async_user, repository.async_owner]).then do |user, owner|
        next false unless user

        User::InteractionAbility.async_interaction_allowed?(
          user: viewer,
          repository: repository,
        ).then do |interaction_allowed|
          next false unless interaction_allowed

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

  def async_viewer_can_delete?(viewer)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(true) if viewer.site_admin?

    async_viewer_cannot_delete_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_delete_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([async_repository, async_deletable_by?(viewer)]).then do |repository, deletable|
      Promise.all([repository.async_network, repository.async_owner]).then do
        load_commit_if_needed do
          context = { repo: repository }
          errors = ContentAuthorizer.authorize(viewer, :CommitComment, :delete, context).errors.map(&:symbolic_error_code)
          if locked_for?(viewer)
            errors << :locked
          end
          errors << :insufficient_access unless deletable
          errors
        end
      end
    end
  end

  def load_commit_if_needed
    if defined?(@commit)
      yield
    else
      Platform::Loaders::GitObject.load(repository, commit_id, expected_type: :commit).then do |commit|
        @commit = commit
        yield
      end
    end
  end

  def async_deletable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_repository.then do |repository|
      next false unless repository

      async_user.then do |user|
        next false unless user
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

    Promise.all([async_repository, async_editable_by?(viewer)]).then do |repository, editable|
      Promise.all([repository.async_network, repository.async_owner]).then do
        load_commit_if_needed do
          context = { repo: repository }
          errors = ContentAuthorizer.authorize(viewer, :CommitComment, :edit, context).errors.map(&:symbolic_error_code)
          if locked_for?(viewer)
            errors << :locked
          end
          errors << :insufficient_access unless editable
          errors
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

    async_repository.then do |repository|
      next false unless repository
      repository.resources.contents.async_writable_by?(actor).then do |is_writable|
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

  def abbreviated_oid
    return if commit_id.blank?

    commit_id[0, Commit::ABBREVIATED_OID_LENGTH]
  end

  def submitted?
    true
  end

  def locked_for?(user)
    return true unless commit
    !commit.can_comment?(user)
  end

  def last_modified_at
    @last_modified_at ||= last_modified_with :user
  end

  # Public: Look for comments on given commits and set the comment_count value
  # attribute for each one.
  #
  # NOTE: This should be used any time many commits will have their comment counts checked.
  #
  # commits    - Array of Commit objects
  # repository - Repository object
  #              (optional, defaults to repository on first passed commit)
  #
  # Returns an array of Commit objects with their comment-count values set
  # (also modifies the passed-in Commit objects)
  def self.attach_counts_to_commits(commits, repository = nil, batch_size: 500)
    return [] if commits.empty?
    repository ||= commits.first.repository
    return commits unless repository

    commits_map = {}

    commits.each do |commit|
      commits_map[commit.oid] = commit
      commit.comment_count = 0
    end

    sql = Arel.sql <<-SQL, repo_id: repository.id
      SELECT commit_id, COUNT(commit_comments.id) as comment_count
        FROM commit_comments
       WHERE repository_id = :repo_id
    SQL

    if GitHub.spamminess_check_enabled?
      sql += Arel.sql <<-SQL
         AND user_hidden = false
      SQL
    end

    commits_map.keys.each_slice(batch_size) do |oids|
      query = Arel.sql <<-SQL, commit_ids: oids
           AND commit_id IN (:commit_ids)
         GROUP BY commit_id
      SQL
      self.connection.select_rows(sql + query).each do |commit_oid, count|
        commit = commits_map[commit_oid]
        commit.comment_count = count
      end
    end

    commits
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo.  Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of Users that can be unsubscribed.
  def unsubscribable_users(users)
    commenters = self.class.select("distinct user_id").where(
      repository_id: repository_id, commit_id: commit_id,
    )
    commenters = Set.new(commenters.map { |c| c.user_id })
    users.reject { |user| commenters.include?(user.id) }
  end

  # Internal: Do the actual WebSocket notification.
  #
  # Returns Array of socket id Strings that were notified.
  def notify_socket_subscribers
    data = {
      timestamp: Time.now.to_i,
      wait:      default_live_updates_wait,
      reason:    "commit comment ##{id} created",
    }

    # Notify associated commit channel that a comment has been created
    channel = GitHub::WebSocket::Channels.commit(repository, commit_id)
    GitHub::WebSocket.notify_repository_channel(repository, channel, data)
  end

  # Collect conditions under which we don't bother checking the content
  # of this Issue for spam.
  def skip_spam_check?
    repository&.private?      ||   # Leave private repos alone.
    repository&.member?(user) ||   # Don't bother repo members.
    user.nil?                 ||
    !user&.can_be_flagged?    ||   # No point in checking these,
    user&.spammy?                  # since nothing will change.
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
      GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:commit_comment"]
      user&.safer_mark_as_spammy(reason: "Commit comment spam (#{permalink}): #{reason}")
    end
  end

  # Is commit comment an "inline note".
  #
  # NOTE: Legacy comments may exist that have a path but no line or position.
  # Just treat these as regular commit comments.
  #
  # Return Boolean.
  def inline?
    path.present? && position.present?
  end

  attr_writer :modifying_user

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the user which we know exists.
  def modifying_user
    @modifying_user ||= (User.find_by(id: GitHub.context[:actor_id]) || user)
  end

  def commit_not_locked
    return true unless commit
    return true if modifying_user.mannequin?
    return true if commit.can_comment?(modifying_user)
    errors.add(:commit_id, "has been locked")
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_readable_by?(actor)
    async_repository.then do |repository|
      next false unless repository
      repository.resources.contents.async_readable_by?(actor)
    end
  end

  def async_notifications_list
    async_repository
  end

  def notifications_thread
    commit
  end

  def notifications_author
    user
  end

  private

  def ensure_creator_is_not_blocked
    if user && repository && user&.blocked_by?([repository&.owner, commit&.committer, commit&.author])
      errors.add :user, "is blocked"
    end
  end

  def clear_blank_path_line
    if path.nil?
      self.line = self.position = nil
    end

    true
  end

  def subscribe_comment_participants
    return unless repository && commit
    subscribe_committer
    subscribe_commenter
  end

  def subscribe_committer
    if committer = (commit.committer || commit.author)
      unless committer == user
        return unless subscribable_by?(committer)
        response = GitHub.newsies.subscribe_to_thread(committer, repository, commit, :author)
        GitHub.newsies.async_subscribe_to_thread(committer.id, repository&.id, commit.oid, :author) if response.failed?
      end
    end
  end

  def subscribe_commenter
    if user
      return unless subscribable_by?(user)
      response = GitHub.newsies.subscribe_to_thread(user, repository, commit, :comment)
      GitHub.newsies.async_subscribe_to_thread(user&.id, repository&.id, commit.oid, :comment) if response.failed?
    end
  end

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns a Newsies::Response instance .
  def get_notification_summary
    list = Newsies::List.new("Repository", repository_id)
    thread = Newsies::Thread.new("Grit::Commit", commit_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end

  def event_payload
    payload = {
      author: self.user,
      commit_comment: self,
      spammy: spammy?,
      allowed: repository.permit?(user, :write),
      repo: repository,
      actor: modifying_user,
      body: body,
    }

    if repository && repository&.in_organization?
      payload[:org] = repository&.organization
    end

    payload
  end

  def instrument_creation
    instrument :create
    GlobalInstrumenter.instrument(
      "commit_comment.create",
      {
        actor: self.user,
        commit_comment: self,
        repository: repository,
      },
    )
  end

  def instrument_update
    previous_body = previous_changes[:body].try(:first)
    instrument :update, changes: { old_body: previous_body, body: body }
    GlobalInstrumenter.instrument(
      "commit_comment.update",
      {
        actor: self.user,
        commit_comment: self,
        previous_body: previous_body,
        repository: repository,
      },
    )
  end

  def instrument_destruction
    instrument :destroy
  end

  # Find all issue mentions in the comment body and create references for
  # them from the commit. This is run after save but only when the body is changed.
  def reference_mentioned_issues
    return if !saved_change_to_body?
    mentioned_issues.each do |issue|
      issue.reference_from_commit(user, commit_id, repository)
    end
  end

  def validate_comment_is_authorized
    return true if modifying_user.mannequin?
    operation = new_record? ? :create : :update
    authorization = ContentAuthorizer.authorize(modifying_user, :commit_comment, operation,
                                                repo: entity)

    if authorization.failed?
      errors.add(:base, authorization.error_messages)
    end
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_commit_comment_id
  end

  # Was the comment body changed in previous_changes? We use this to determine
  # if body changes _only_ after_commit.
  def body_changed_after_commit?
    previous_changes.key?(:body)
  end
end
