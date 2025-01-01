# typed: true
# frozen_string_literal: true

class Discussion < ApplicationRecord::Domain::Discussions
  include Spam::Spammable
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include AuthorAssociable
  include UserContentEditable
  include GitHub::UTF8
  include OrgBlockable
  include AbuseReportable
  include Referenceable
  include Referrer
  include InteractionBanValidation
  include GitHub::UserContent
  include NotificationsContent::WithCallbacks
  include GitHub::Relay::GlobalIdentification
  include Discussion::NewsiesAdapter
  include Reaction::Subject::RepositoryContext
  include Discussion::SearchAdapter
  include Instrumentation::Model
  include Discussion::LockingDependency
  include Discussion::StateDependency
  include Discussion::StateReasonable
  include Discussion::TransferAdapter
  include Discussion::HovercardDependency
  include Votable
  include Reactable
  include Storage::UserAssetTransfer::SavedReplyCopyDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Discussion

  UPDATE_SCORE_INTERVAL = 10.seconds.to_i

  # Text used for onboarding new discussion users
  WELCOME_BODY = <<-WELCOME
<!--
    ✏️ Optional: Customize the content below to let your community know what you intend to use Discussions for.
-->
## 👋 Welcome!
  We’re using Discussions as a place to connect with other members of our community. We hope that you:
  * Ask questions you’re wondering about.
  * Share ideas.
  * Engage with other community members.
  * Welcome others and are open-minded. Remember that this is a community we
  build together 💪.

  To get started, comment below with an introduction of yourself and tell us about what you do with this community.

<!--
  For the maintainers, here are some tips 💡 for getting started with Discussions. We'll leave these in Markdown comments for now, but feel free to take out the comments for all maintainers to see.

  📢 **Announce to your community** that Discussions is available! Go ahead and send that tweet, post, or link it from the website to drive traffic here.

  🔗 If you use issue templates, **link any relevant issue templates** such as questions and community conversations to Discussions. Declutter your issues by driving community content to where they belong in Discussions. If you need help, here's a [link to the documentation](#{GitHub.help_url}/github/building-a-strong-community/configuring-issue-templates-for-your-repository#configuring-the-template-chooser).

  ➡️ You can **convert issues to discussions** either individually or bulk by labels. Looking at you, issues labeled “question” or “discussion”.
-->
  WELCOME

  attribute :title, StringFromBinary.new
  attribute :body, StringFromBinary.new

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain required: true, legacy_return_type: true
  belongs_to :user
  belongs_to :chosen_comment, class_name: "DiscussionComment"
  belongs_to :issue
  belongs_to :release
  belongs_to :team_discussion, foreign_key: :team_post_id, class_name: "DiscussionPost", inverse_of: false
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration, foreign_key: :performed_by_integration_id, class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  belongs_to :category, foreign_key: :discussion_category_id, class_name: "DiscussionCategory", required: true
  # rubocop:enable Rails/InverseOf
  alias_attribute :category_id, :discussion_category_id

  has_many :applied_discussion_labels
  has_many :labels, through: :applied_discussion_labels, disable_joins: true

  # Indicates the current state of the Discussion with respect to whether it's being converted
  # from an Issue or not, if conversation has been locked, or if it's being transferred
  # to another Repository.
  enum :state, {
    open: 0,
    converting: 1,
    error: 2,
    # 3 belonged to `locked`, which was replaced by locked_at
    # in https://github.com/github/discussions/issues/2846
    transferring: 4,
    closed: 5,
    draft: 6,
    scheduled: 7,
  }

  # Indicates what went wrong if this Discussion was originally an Issue and the conversion
  # process failed, or if transferring this Discussion to another Repository failed.
  enum :error_reason, {
    no_error: 0,
    comment_copy_failure: 1,
    close_failure: 2,
    reset_conversion_failure: 3,
  }

  # We had multiple discussion types at one point. We don't anymore,
  # but maybe we will in the future!
  enum :discussion_type, {
    default: 0,
  }

  has_many :comments, -> { order("discussion_comments.created_at ASC") },
    class_name: "DiscussionComment",
    inverse_of: :discussion
  destroy_dependents_in_background :comments

  has_many :commenters, through: :comments, source: :user, disable_joins: true
  has_many :votes, class_name: "DiscussionVote"
  destroy_dependents_in_background :votes

  has_many :upvotes, -> { where("discussion_votes.upvote = 1") }, class_name: "DiscussionVote"
  has_many :downvotes, -> { where("discussion_votes.upvote = 0") }, class_name: "DiscussionVote"

  has_many :events, -> { where(event_type: DiscussionEvent.event_types.values).order(:id) }, class_name: "DiscussionEvent"
  destroy_dependents_in_background :events

  has_many :reactions, class_name: "DiscussionReaction"
  destroy_dependents_in_background :reactions

  has_one :spotlight, class_name: "DiscussionSpotlight", dependent: :destroy

  has_one :category_pin, class_name: "DiscussionCategoryPin", dependent: :destroy

  # rubocop:todo Rails/InverseOf
  has_one :last_transfer, class_name: "DiscussionTransfer", foreign_key: :new_discussion_id
  # rubocop:enable Rails/InverseOf

  has_one :poll, class_name: "DiscussionPoll", dependent: :destroy, inverse_of: :discussion
  accepts_nested_attributes_for :poll

  setup_spammable(:user)
  setup_attachments
  setup_referrer

  # Use VARBINARY limit from the database
  TITLE_BYTESIZE_LIMIT = 1024

  before_validation :set_number!, on: :create
  before_validation :initial_bump, on: :create
  before_validation :strip_title
  before_validation :set_release_defaults, on: :create, if: :release
  before_validation :cannot_change_poll_discussion_category, on: :update, if: :discussion_category_id_changed?
  before_validation :cannot_change_to_poll_discussion_category, on: :update, if: :discussion_category_id_changed?

  validates :title, :number, :bumped_at, presence: true
  validate :user_exists_when_open_state, on: :create
  validate :chosen_comment_matches_discussion
  validate :discussion_is_question_if_chosen_comment_set
  validate :ensure_author_is_not_blocked, on: :create, unless: :skip_user_blocking_validation
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }
  validates :body, unicode: true, allow_blank: true, allow_nil: true, if: :body_can_be_empty?
  validates :body, presence: true, on: :create, unless: :body_can_be_empty?
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }, unicode: true
  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :category_is_accessible, if: :category_id_changed?
  validate :issue_or_team_discussion_present_if_converting
  validate :error_reason_present_if_error
  validate :user_has_verified_email, on: :create
  validate :category_belongs_to_same_repo
  validate :category_is_not_deleting
  validates_associated :poll

  with_options if: :scheduled? do
    validates :publish_at, presence: true,
              comparison: {
                greater_than_or_equal_to: ->(_rec) { 1.minute.from_now },
                less_than_or_equal_to: ->(_rec) { 3.months.from_now }
              }
  end

  before_update :maybe_bump_on_changes

  after_save_commit(
    :detect_comment_language,
    if: -> do
      T.bind(self, Discussion)
      previous_changes.key?(:body)
    end,
    unless: -> { GitHub.enterprise? }
  )

  # Live updates
  after_commit :notify_socket_subscribers, on: :update
  after_commit(
    :notify_socket_subscribers_for_chosen_comment,
    on: :update,
    if: -> do
      T.bind(self, Discussion)
      previous_changes.key?(:chosen_comment_id)
    end
  )
  after_commit(
    :notify_summary_socket_subscribers,
    on: :update,
    if: -> do
      T.bind(self, Discussion)
      previous_changes.key?(:body) || previous_changes.key?(:comment_count)
    end
  )

  # Category Pins
  after_commit(
    :destroy_category_pin, on: :update,
    if: -> do
      T.bind(self, Discussion)
      previous_changes.key?(:discussion_category_id)
    end
  )

  # Notifications
  after_commit :subscribe_and_notify, on: :create
  after_commit :update_subscriptions_and_notify, on: :update
  after_destroy :destroy_notification_summary

  # Used to temporarily hold the current user, for use in logging to Hydro
  attr_accessor :actor
  attr_accessor :skip_user_blocking_validation

  # Set in the discussion builder and used for logging to Hydro
  attr_accessor :created_from_category_template

  # Distinguish between deletion and transfer
  attr_accessor :deletion_hook_action

  # params that help prefill an discussion for discussion forms
  # prefilled by PrefilledDiscussionFields
  attr_accessor :structured_template_inputs

  # Hydro telemetry and audit logs
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update, if: :instrumentable_change_after_commit?
  after_commit :instrument_publish_event, on: :update
  before_destroy :generate_webhook_payload
  after_destroy_commit :instrument_deletion_event

  # audit log for updates
  after_commit :audit_log_update_event, on: :update, if: :auditable_change_after_commit?

  # Search
  after_commit :synchronize_search_index

  after_commit :create_initial_upvote, on: :create

  # Community Insights data
  after_commit :count_daily_contributors, on: [:create, :destroy]

  scope :for_repository, ->(repo) { where(repository_id: repo) }
  scope :for_organization, ->(org, only_repo_ids: nil) do
    return Discussion.none unless org
    repo_scope = Repository.active.where(organization_id: org)
    repo_scope = repo_scope.where(id: only_repo_ids) if only_repo_ids
    repo_ids = repo_scope.pluck(:id)
    for_repository(repo_ids)
  end
  scope :with_number, ->(number) { where(number: number) }
  scope :converted_from_issue, ->(issue) { where(issue_id: issue) }
  scope :converted_from_issue_numbered, ->(number) do
    where(number: number).where.not(issue_id: nil)
  end
  scope :converted_from_team_discussion, ->(team_discussion) { where(team_post_id: team_discussion) }
  scope :authored_by, ->(user) { where(user_id: user) }
  scope :answerables, -> { joins(:category).where(category: { supports_mark_as_answer: true }) }
  scope :answered, -> { answerables.where.not(chosen_comment_id: nil) }
  scope :unanswered, -> { answerables.where(chosen_comment_id: nil) }
  scope :verified, -> { answerables.where.not(verified_at: nil) }
  scope :unverified, -> { answerables.where(verified_at: nil) }
  scope :newest_first, -> { order("discussions.created_at DESC") }
  scope :oldest_first, -> { order("discussions.created_at ASC") }
  scope :recently_bumped_first, -> { order("discussions.bumped_at DESC") }
  scope :least_recently_updated_first, -> { order("discussions.updated_at ASC") }
  scope :most_commented_first, -> { order("discussions.comment_count DESC") }
  scope :least_commented_first, -> { order("discussions.comment_count ASC") }
  scope :highest_score_first, -> { order("discussions.score DESC") }
  scope :lowest_score_first, -> { order("discussions.score ASC") }
  scope :most_upvotes_first, -> { order(total_upvotes: :desc) }
  scope :updated_since, ->(time) { where("discussions.updated_at > ?", time) }
  scope :created_since, -> (time) { where("discussions.created_at > ?", time) }
  scope :for_created_issue, ->(issue) { joins(:events).where(events: { issue_id: issue }) }
  scope :filter_by_categories, -> (category_ids) { where(category_id: category_ids) }
  scope :ready_to_publish, -> { scheduled.where(publish_at: ..Time.current) }

  scope :commented_on_by, ->(user) do
    discussion_ids = DiscussionComment.for_user(user).select(:discussion_id).distinct
    where(id: discussion_ids)
  end

  scope :authored_by_and_visible_to, ->(user) do
    visible_repo_ids = user.associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    visible_active_repo_ids = Repository.active.where(id: visible_repo_ids).pluck(:id)
    authored_discussion_repo_ids = authored_by(user).distinct.pluck(:repository_id)
    public_repo_ids = Repository.active.where(id: authored_discussion_repo_ids).public_scope.
      pluck(:id)
    authored_by(user).for_repository(visible_active_repo_ids | public_repo_ids)
  end

  scope :commented_on_and_visible_to, ->(user) do
    visible_repo_ids = user.associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    visible_active_repo_ids = Repository.active.where(id: visible_repo_ids).pluck(:id)
    commented_discussion_repo_ids = commented_on_by(user).distinct.pluck(:repository_id)
    public_repo_ids = Repository.active.where(id: commented_discussion_repo_ids).public_scope.
      pluck(:id)
    commented_on_by(user).for_repository(visible_active_repo_ids | public_repo_ids)
  end

  scope :sorted_by, ->(filter) do
    if filter == "oldest"
      oldest_first
    elsif filter == "most_commented"
      most_commented_first
    elsif filter == "least_commented"
      least_commented_first
    elsif filter == "highest_score"
      highest_score_first
    elsif filter == "lowest_score"
      lowest_score_first
    elsif filter == "newest"
      newest_first
    elsif filter == "least_recently_updated"
      least_recently_updated_first
    else
      recently_bumped_first
    end
  end

  scope :filter_by_type, ->(type) do
    case type
    when "unanswered"
      unanswered
    when "answered"
      answered
    else
      all
    end
  end

  SUGGESTION_LIMIT = 1000

  scope :suggestions, -> do
    select("id AS id, number, title, state, state_reason, updated_at").
      order("updated_at desc").
      limit(SUGGESTION_LIMIT)
  end

  # Override Reactable.reactions_by_reactable_ids to use discussion reactions
  # table
  sig { params(ids: T.untyped).returns(T.untyped) }
  def self.reactions_by_reactable_ids(ids)
    DiscussionReaction.
      where(discussion_id: ids).
      select(:discussion_id, :content, :user_id).
      group_by(&:discussion_id)
  end

  # Public: Provides a representation of the original post of a discussion with its poll.
  #
  # body - the String text of a discussion body
  # poll - a DiscussionPoll, a String representing a DiscussionPoll, or nil
  #
  # Returns a String.
  sig { params(body: T.untyped, poll: T.untyped).returns(T.untyped) }
  def self.body_with_poll(body, poll)
    return body unless poll.present?
    text = <<~MARKDOWN
      #{body.strip}

      ----

      Poll: #{poll}
    MARKDOWN
    text.strip
  end

  # TODO: define a scope the returns the discussions' repos' owners
  # so that we can remove the N+1 in the filtering we use this for
  sig { returns T.any(Symbol, User, Organization) }
  def target_for_conditional_access
    owner = repository_owner
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  sig { returns Promise[T.any(Symbol, User, Organization)] }
  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  # Returns formatted discussion body that will be used when creating an issue from discussion
  sig { returns(T.untyped) }
  def async_formatted_body
    Platform::Loaders::ActiveRecord.load(::User, self.user_id).then do |discussion_user|
      self.user = discussion_user || User.ghost
      DiscussionOpTextFormatter.new(self).format
    end
  end

  # Determines the target for for conditional access for multiple Discussion instances
  #
  # discussions - an enumerable of Discussion
  #
  # returns Hash[Discussion] => target for conditional access
  sig { params(discussions: T::Array[Discussion]).returns(T::Hash[Discussion, T.any(Symbol, User)]) }
  def self.multiple_target_for_conditional_access(discussions)
    ConditionalAccess::Filter.ensure_with_class(discussions, Discussion)
    repositories = Repository.where(id: discussions.pluck(:repository_id))
    repository_to_target = Repository.multiple_target_for_conditional_access(repositories)
    repository_id_to_target = repository_to_target.transform_keys { |k| k.id }
    discussions.each_with_object({}) { |v, h| h[v] = repository_id_to_target[v.repository_id] }
  end

  # Public: Get a subset of discussions that do not include those in repositories owned
  # by the specified list of organizations.
  #
  # discussions - a list of Discussion records
  # org_ids - a list of Organization IDs whose discussions should be omitted
  #
  # Returns an Array of Discussions.
  sig { params(discussions: T.untyped, org_ids: T.untyped).returns(T.untyped) }
  def self.filter_out_org_discussions(discussions:, org_ids:)
    discussions.reject do |discussion|
      org_ids.include?(discussion.organization_id)
    end
  end

  # Public: When did the specified user last view this discussion? Used to identify which timeline items are "new".
  sig { params(viewer: T.nilable(User)).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_read_at_for(viewer:)
    key = last_read_at_cache_key_for(viewer: viewer)
    return unless key
    last_read_at_src = Discussions::Kv.store.get(key).value { nil }
    Time.zone.parse(last_read_at_src) if last_read_at_src
  end

  # Public: Get the key used to store a particular user's last read time for this discussion in the key-value store.
  #
  # Returns a String appropriate to use in the key-value store, or nil if the given viewer is not a valid one for
  # persisting a last-read time in the key-value store.
  sig { params(viewer: T.nilable(User)).returns(T.nilable(String)) }
  def last_read_at_cache_key_for(viewer:)
    return unless viewer
    "read:discussion:#{id}:#{viewer.id}"
  end

  # Public: Persist the time the specified viewer last read this discussion.
  #
  # viewer - a User or nil
  # time - a DateTime
  #
  # Returns a Boolean indicating success.
  sig { params(viewer: T.nilable(User), time: T.nilable(T.any(Time, DateTime))).returns(T::Boolean) }
  def set_last_read_at_for(viewer:, time:)
    return false unless time
    key = last_read_at_cache_key_for(viewer: viewer)
    return false unless key
    Discussions::Kv.store.set(key, time.iso8601, expires: 60.days.from_now)
    true
  end

  sig { returns(T::Boolean) }
  def ready_to_publish?
    scheduled? && publish_at <= Time.current
  end

  sig { void }
  def set_release_defaults
    release = self.release
    return unless release
    self.title = release.display_name
    self.body = [release.body, "<hr /><em>This discussion was created from the release <a href='#{release.permalink}'>#{release.display_name}</a>.</em>"].compact.join("\n\n")
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def unmark_answer_if_set(actor)
    # If it's not answered, don't need to unmark anything
    return true unless answered?

    chosen_comment = T.must_because(self.chosen_comment) { "#answered? ensures chosen_comment is non-nil" }

    # Set the actor so we can log a Hydro event about the comment being updated
    chosen_comment.actor = actor

    chosen_comment.unmark_as_answer
  end

  # Public: This instance is a discussion. Useful for partials or helpers that can accept Issues, PullRequests, or
  # Discussions.
  sig { returns TrueClass }
  def discussion?
    true
  end

  # Public: A Discussion is never a PullRequest. Useful for partials or helpers that can accept Issues, PullRequests,
  # or Discussions.
  sig { returns FalseClass }
  def pull_request?
    false
  end

  # Public: Is this discussion publicly visible?
  sig { returns T.nilable(T::Boolean) }
  def public?
    repository&.public?
  end

  sig { returns T::Boolean }
  def organization_discussion?
    async_organization_discussion?.sync
  end

  sig { returns Promise[T::Boolean] }
  def async_organization_discussion?
    async_repository.then do |repo|
      next false unless repo

      repo.async_organization_discussion.then do |organization_discussion|
        next false unless organization_discussion.present?
        organization_discussion.repository_id == repository_id
      end
    end
  end

  # Public: The ID of the organization that owns the repository this discussion belongs to,
  # if any.
  sig { returns T.nilable(Integer) }
  def organization_id
    repository&.organization_id
  end

  # Public: Append a collection of labels to this discussion and re-index the discussion for search. Labels already
  # applied to this discussion will be silently ignored.
  sig { params(labels: T.untyped).returns(T.untyped) }
  def add_labels(labels)
    existing = Set.new(self.labels.pluck(:id))
    new_labels = labels.reject { |label| existing.include?(label.id) }
    return if new_labels.empty?

    self.labels << new_labels

    new_labels.each { |l| instrument_labeled_event(l) }

    synchronize_search_index
  end

  # Public: Replace the collection of labels applied to this discussion and re-index the discussion for search. Use this
  # instead of calling `labels=` directly to ensure the search index is up to date.
  sig { params(labels: T.untyped).returns(T.untyped) }
  def replace_labels(labels)
    original_labels = self.labels.to_a.dup

    self.labels = labels

    labeled   = self.labels - original_labels
    unlabeled = original_labels - self.labels.to_a

    labeled.each { |l| instrument_labeled_event(l) }
    unlabeled.each { |l| instrument_unlabeled_event(l) }

    synchronize_search_index
  end

  # Public: Remove several labels from this discussion and re-index the discussions for search.
  sig { params(labels: T.untyped).returns(T.untyped) }
  def delete_labels(labels)
    existing = Set.new(self.labels.pluck(:id))
    removed_labels = labels.reject { |label| existing.include?(label) }
    self.labels.delete(removed_labels)

    removed_labels.each { |label| instrument_unlabeled_event(label) }

    synchronize_search_index
  end

  # Public: Remove all labels from this discussion and re-index the discussion for search.
  sig { void }
  def clear_labels
    removed_labels = self.labels.to_a.dup
    self.labels.clear

    removed_labels.each { |label| instrument_unlabeled_event(label) }

    synchronize_search_index
  end

  sig { params(label: Label).void }
  def instrument_labeled_event(label)
    GlobalInstrumenter.instrument "discussion.add_label", discussion: self, label: label, actor: safe_actor
    instrument :label, action: :labeled, actor: safe_actor, label: label

    GlobalInstrumenter.instrument "discussions_label", {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: self.id,
      discussion: discussion,
      actor_id: safe_actor&.id,
      actor: safe_actor,
      action: :ACTION_LABEL_ADDED,
      action_timestamp: Time.now,
      label_id: label.id
    }
  end

  sig { params(label: Label).void }
  def instrument_unlabeled_event(label)
    GlobalInstrumenter.instrument "discussion.remove_label", discussion: self, label: label, actor: safe_actor
    instrument :unlabel, action: :unlabeled, actor: safe_actor, label: label

    GlobalInstrumenter.instrument "discussions_label", {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: self.id,
      discussion: discussion,
      actor_id: safe_actor&.id,
      actor: safe_actor,
      action: :ACTION_LABEL_REMOVED,
      action_timestamp: Time.now,
      label_id: label.id
    }
  end

  # Public: Return a Set containing the IDs of labels applied to this discussion.
  #
  # Returns a Set containing integer IDs.
  sig { returns T::Set[Integer] }
  def unique_label_ids
    @unique_label_ids ||= Set.new(label_ids)
  end

  sig { returns(T.untyped) }
  def creation_rate_limit_configuration
    GitHub.discussion_creation_rate_limit_configuration
  end

  # Public: Get label names for use suggesting labels for discussions in the specified repository.
  #
  # repo - a Repository whose labels should be returned
  # limit - how many label names to return
  #
  # Returns an Array of String names of Label records.
  sig { params(repo: T.untyped, limit: T.untyped).returns(T.untyped) }
  def self.label_name_suggestions_for(repo, limit: 1_000)
    label_ids = repo.applied_discussion_labels
      # Sort by the most widely used labels first, then if two labels have been applied to the same number of
      # discussions, sort the label for the most recent discussion first:
      .group(:label_id).order(Arel.sql("COUNT(*) DESC, MAX(discussion_id) DESC"))
      .limit(limit).pluck(:label_id)
    label_names = Label.where(id: label_ids).order(:lowercase_name).pluck(:name)
    label_names.map do |label_name|
      if /\s|"/.match?(label_name)
        "\"#{label_name.gsub('"', '\\\"')}\""
      else
        label_name
      end
    end
  end

  sig { returns(T.untyped) }
  def apply_dynamic_rate_limit_configuration?
    return @apply_dynamic_rate_limit_configuration if defined?(@apply_dynamic_rate_limit_configuration)
    @apply_dynamic_rate_limit_configuration = \
      FeatureFlag.vexi.enabled_or_raise?(:discussions_dynamic_creation_rate_limits, user) && # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      creation_rate_limit_configuration.present?
  end

  # Public: Returns the logins of users who have most recently authored a discussion in the given repository.
  #
  # repo - a Repository or its ID
  # viewer - the currently authenticated User or nil
  # limit - how many unique author logins to return
  #
  # Returns an ordered Array of String logins.
  sig { params(repo: T.untyped, viewer: T.untyped, limit: T.untyped).returns(T.untyped) }
  def self.author_login_suggestions_for(repo, viewer: nil, limit: 1_000)
    author_ids = for_repository(repo).filter_spam_for(viewer).limit(limit)
      # Sort by the most prolific authors first, then if two authors have the same number of discussions, sort
      # the most recent author first:
      .group(:user_id).order(Arel.sql("COUNT(*) DESC, MAX(id) DESC"))
      .pluck(:user_id)
    author_logins = User.where(id: author_ids).by_login.pluck(:display_login).to_set
    viewer_login = viewer&.display_login
    if viewer_login && author_logins.include?(viewer_login)
      [viewer_login] + author_logins.delete(viewer_login).to_a
    else
      author_logins.to_a
    end
  end

  # Public: Returns a new, unsaved Discussion with content taken from the given Issue. The new Discussion will belong to
  # the provided category.
  #
  # category - A DiscussionCategory from the same repository as the issue.
  sig { params(issue: T.untyped, category: T.untyped).returns(T.untyped) }
  def self.from_issue(issue, category:)
    latest_comment_creation = issue.comments.not_spammy.maximum(:created_at)
    bumped_at = latest_comment_creation || issue.created_at

    Discussion.new(title: issue.title, body: issue.body, repository: issue.repository,
                   category: category, user: issue.safe_user, user_hidden: issue.user_hidden,
                   comment_count: issue.issue_comments_count, created_at: issue.created_at,
                   updated_at: issue.updated_at, issue_id: issue.id,
                   state: :converting, bumped_at: bumped_at, skip_user_blocking_validation: true)
  end

  # Public: Returns a new, unsaved Discussion with content taken from the given DiscussionPost (a team discussion,
  # also called a team post). The new Discussion will belong to the provided repository and category.
  #
  # discussion_post - a DiscussionPost
  # repository - A Repository for the new team discussion.
  # category - A DiscussionCategory from the repository where the team discussion will be posted.
  #
  # Returns an unsaved Discussion.
  sig { params(discussion_post: T.untyped, repository: T.untyped, category: T.untyped).returns(T.untyped) }
  def self.from_team_discussion(discussion_post, repository:, category:)
    latest_comment_creation = discussion_post.replies.maximum(:created_at)
    bumped_at = latest_comment_creation || discussion_post.created_at
    user_hidden = discussion_post.user&.spammy? || false

    Discussion.new(title: discussion_post.title, body: discussion_post.body, repository: repository,
                   category: category, user: discussion_post.user, user_hidden: user_hidden,
                   comment_count: discussion_post.replies.count, created_at: discussion_post.created_at,
                   updated_at: discussion_post.updated_at, team_post_id: discussion_post.id,
                   state: :converting, bumped_at: bumped_at, skip_user_blocking_validation: true)
  end

  sig { returns User }
  def author
    user || User.ghost
  end

  sig { returns T::Boolean }
  def authored_by_ghost?
    author.ghost?
  end

  # Internal: For suggestions_params helper
  sig { returns(T.untyped) }
  def suggestion_id
    id
  end

  # Public: Returns an existing DiscussionVote from the given User for this Discussion.
  sig { params(user: T.untyped, upvote: T.untyped).returns(T.untyped) }
  def vote_by(user, upvote:)
    votes.where(upvote: upvote).for_user(user).first
  end

  # Public: Creates a DiscussionVote for the given User for this Discussion, if one does
  # not already exist. Returns true on success, or if the User has already voted on this
  # Discussion, and false on failure.
  sig { params(user: T.untyped, upvote: T.untyped).returns(T.untyped) }
  def create_vote_for(user, upvote:)
    vote = DiscussionVote.retry_on_find_or_create_error do
      votes.for_user(user).first ||
      DiscussionVote.new(discussion: discussion, user: user)
    end
    vote.upvote = upvote
    vote.save
    vote
  end

  sig { params(user: T.untyped).returns(T.untyped) }
  def upvote(user)
    create_vote_for(user, upvote: true)
  end

  # Public: Users who should be considered discussion participants.
  #
  # viewer - the User who is viewing the participants (current_user)
  # optimize_repo_access_checks - if optimize_repo_access_checks is set
  #                               to true, do not perform access checks
  #                               on repos that are owned by org's with
  #                               a lot of members
  # limit - limit the query of participants, default: no limit
  #
  # Returns an Array of Users.
  sig { params(viewer: T.untyped, optimize_repo_access_checks: T.untyped, limit: T.untyped).returns(T.untyped) }
  def participants_for(viewer, optimize_repo_access_checks: false, limit: nil)
    self.class.filter_users_for(viewer, participants(
      viewer: viewer,
      optimize_repo_access_checks: optimize_repo_access_checks,
      limit: limit&.floor, # Convert to an integer to cater for limit: ONE_POINT_FIVE_TIMES_MAX_AVATARS
    ))
  end

  # Public: Find all Users that have commented on this discussion.
  # Exclude Bots and users who no longer have access to this repo
  # (unless parent org has so many members that query may timeout).
  # Exclude Organizations from results as participants should be Users, but
  # Users can transform into Organizations.
  #
  # Note that the returned users are not filtered for spam.
  #
  # optimize_repo_access_checks - by default, #user_ids_to_hide_from_mentions will
  #                               check to make sure that each user returned still
  #                               has access to the repo. If optimize_repo_access_checks
  #                               is set to true, that check will not happen if the
  #                               parent org has too many members (which may
  #                               cause the access checks to time out)
  # limit - limit the query of participants, default: no limit
  #
  # Returns an Array of Users.
  sig { params(viewer: T.nilable(User), optimize_repo_access_checks: T::Boolean, limit: T.nilable(Integer)).returns(T::Array[User]) }
  def participants(viewer: nil, optimize_repo_access_checks: false, limit: nil)
    @participants ||= {}
    args = [optimize_repo_access_checks, limit]
    return @participants[args] if @participants.key?(args)

    @participants[args] = self.class.load_users(participant_user_ids(viewer: viewer), limit: limit)
  end

  sig { params(viewer: T.untyped, users: T.untyped).returns(T.untyped) }
  def self.filter_users_for(viewer, users)
    users.reject { |user| user.hide_from_user?(viewer) }
  end

  sig { params(user_ids: T.untyped, limit: T.untyped).returns(T.untyped) }
  def self.load_users(user_ids, limit: nil)
    scope = User.where(id: user_ids, type: "User")
    scope = scope.limit(limit) if limit.present?
    scope.to_a.sort_by { |user| user_ids.index(user.id) }
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def participant_count(viewer:)
    participants_for(viewer).count
  end

  sig { params(viewer: T.nilable(User)).returns(T::Array[Integer]) }
  def participant_user_ids(viewer: nil)
    user_ids = Set.new
    comments_scope = comments.unscope(:order).distinct
    discussion_post_as_admin_enabled =
      viewer&.feature_flag_enabled?(:discussion_post_as_admin, default: false) || FeatureFlag.vexi.enabled?(:discussion_post_as_admin, default: false)
    can_view_original_author = viewer&.site_admin? || viewer&.employee?

    if !discussion_post_as_admin_enabled || can_view_original_author
      user_ids.add(user_id)
    else
      user_ids.add(user_id) unless post_as_admin?
      comments_scope = comments_scope.where(post_as_admin: false)
    end

    user_ids.merge(comments_scope.pluck(:user_id)).to_a
  end

  # Public: Get user IDs who participated in the specified discussions.
  #
  # discussions - a list of Discussions
  # viewer - the current User or nil
  #
  # Returns a hash of discussion ID => user IDs for all the participants in the
  # specified discussions.
  sig { params(discussions: T.untyped, viewer: T.untyped).returns(T.untyped) }
  def self.participant_ids_by_discussion_id(discussions, viewer:)
    discussion_post_as_admin_enabled =
      viewer&.feature_flag_enabled?(:discussion_post_as_admin, default: false) || FeatureFlag.vexi.enabled?(:discussion_post_as_admin, default: false)
    can_view_post_as_admin_author = viewer&.site_admin? || viewer&.employee?

    discussion_comments = DiscussionComment.for_discussion(discussions.map(&:id))
      .filter_spam_for(viewer)
      .distinct

    if discussion_post_as_admin_enabled && !can_view_post_as_admin_author
      discussion_comments = discussion_comments.where(post_as_admin: false)
    end

    # Group comment user_ids by discussion_id
    commenter_ids_by_discussion_id = {}
    discussion_comments.pluck(:discussion_id, :user_id).each do |discussion_id, user_id|
      commenter_ids_by_discussion_id[discussion_id] ||= []
      commenter_ids_by_discussion_id[discussion_id] << user_id
    end

    results = Hash.new([])
    discussions.each do |discussion|
      commenter_ids = commenter_ids_by_discussion_id[discussion.id] || []

      # Include the discussion author unless it's an admin post that should be hidden
      should_include_author = !discussion.post_as_admin? || (discussion_post_as_admin_enabled && can_view_post_as_admin_author)

      participant_ids = if should_include_author
        [discussion.user_id] + commenter_ids
      else
        commenter_ids
      end

      results[discussion.id] = participant_ids.uniq
    end

    results
  end

  # Public: Get users who participated in the given discussions.
  #
  # discussions - a list of Discussions
  # viewer - the current User or nil
  #
  # Returns a Hash of Discussion ID => Array of Users.
  sig { params(discussions: T.untyped, viewer: T.untyped).returns(T.untyped) }
  def self.participants_by_discussion_id(discussions, viewer:)
    user_ids_by_discussion_id = participant_ids_by_discussion_id(discussions, viewer: viewer)
    user_ids = user_ids_by_discussion_id.values.flatten.uniq
    users_by_id = filter_users_for(viewer, load_users(user_ids)).index_by(&:id)
    results = Hash.new([])
    user_ids_by_discussion_id.each do |discussion_id, user_ids|
      results[discussion_id] = users_by_id.slice(*user_ids).values
    end
    results
  end

  sig { returns String }
  def to_param
    number.to_s
  end

  # Public: Can the given actor delete the discussion?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def deletable_by?(actor)
    response = ::Permissions::Enforcer.authorize(
      action: :delete_discussion,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  # Public: Can the given actor delete the discussion?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_deletable_by?(actor)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :delete_discussion,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Can the given actor change the title and body of this discussion?
  sig { params(actor: T.untyped).returns(T::Boolean) }
  def modifiable_by?(actor)
    async_modifiable_by?(actor).sync
  end

  sig { params(actor: T.untyped, skip_interaction_check: T.untyped).returns(T.untyped) }
  def async_modifiable_by?(actor, skip_interaction_check: false)
    return Promise.resolve(false) unless actor

    async_repository.then do |repository|
      interaction_allowed_promise =
        if skip_interaction_check
          Promise.resolve(true)
        else
          User::InteractionAbility.async_interaction_allowed?(user: actor, repository: repository)
        end

      authzd_promise = Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :edit_discussion,
        actor: actor,
        subject: self,
      ).then { |decision| decision.allow? }

      Promise.all([interaction_allowed_promise, authzd_promise]).then { |results| results.all? }
    end
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def category_modifiable_by?(actor)
    return false unless actor

    response = ::Permissions::Enforcer.authorize(
      action: :edit_category_on_discussion,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_category_modifiable_by?(actor)
    return Promise.resolve(false) unless actor

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :edit_category_on_discussion,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Returns self. This is useful when rendering a discussion along with
  # its comments.
  sig { returns Discussion }
  def discussion
    self
  end

  # Public: Returns the ID of this Discussion.
  sig { returns(T.untyped) }
  def discussion_id
    id
  end

  # Public: Returns nil because this is a Discussion not a DiscussionComment.
  sig { returns NilClass }
  def discussion_comment_id
    nil
  end

  # Public: Returns true if this discussion is taking place in an organization-owned repository.
  sig { returns T::Boolean }
  def in_organization?
    repository_owner.is_a?(Organization)
  end

  sig { returns T.nilable(T::Boolean) }
  def archived_repository?
    repository&.archived?
  end

  sig { returns T::Boolean }
  def instrumentable_change_after_commit?
    %i[title body discussion_category_id state state_reason locked_at converted_at].any? do |key|
      previous_changes.key?(key)
    end
  end

  sig { returns T::Boolean }
  def auditable_change_after_commit?
    previous_changes.key?(:title) || previous_changes.key?(:body)
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def filter_spam_comments_for(actor)
    comments.filter_spam_for(actor)
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def filter_spam_events_for(actor)
    filtered_events = []
    ordered_events = events.to_a
    GitHub::PrefillAssociations.prefill_associations(ordered_events, [:actor, :issue, comment: :user, discussion_transfer: :old_repository])
    promises = ordered_events.map do |event|
      event.discussion = self
      event.async_readable_by?(actor)
    end
    readable_checks = Promise.all(promises).sync
    ordered_events.each_with_index do |event, i|
      filtered_events << event if readable_checks[i]
    end
    filtered_events
  end

  sig { returns(T.untyped) }
  def last_event
    association(:events).loaded? ? association(:events).target.last : events.last
  end

  # Public: Returns an Array of DiscussionEventGroup and DiscussionEvent records.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def unsorted_filtered_and_grouped_events_for(actor)
    events = filter_spam_events_for(actor)
    events = filter_issue_events_for_repo_without_issues(events)
    event_grouper = DiscussionEventGrouper.new(events)
    groups = event_grouper.group_events
    remaining_events = event_grouper.ungrouped_events
    groups + remaining_events
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def timeline_events_for(actor)
    unsorted_filtered_and_grouped_events_for(actor).sort_by(&:created_at)
  end

  # Public: Can this user create a new discussion comment?
  #
  # actor - a User
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_comment?(actor)
    return false if publishable?

    response = Permissions::Enforcer.authorize(
      action: :create_discussion_comment,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_toggle_answer?(actor)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :toggle_discussion_answer,
      actor: actor,
      subject: self
    ).then { |decision| decision.allow? }
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_comment?(actor)
    return Promise.resolve(false) if publishable?

    return Promise.resolve(false) unless actor

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :create_discussion_comment,
      actor: actor,
      subject: self
    ).then { |decision| decision.allow? }
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def viewer_can_update?(viewer)
    return false unless repository
    viewer_cannot_update_reasons(viewer).empty?
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def async_viewer_can_update?(viewer)
    async_repository.then do |repo|
      next false unless repo
      viewer_cannot_update_reasons(viewer).empty?
    end
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def viewer_cannot_update_reasons(viewer)
    return [:login_required] unless viewer
    context = { repo: repository, discussion: self }
    errors = ContentAuthorizer.authorize(viewer, :Discussion, :edit, context).errors.
      map(&:symbolic_error_code)
    errors << :insufficient_access unless modifiable_by?(viewer)
    errors
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_readable_by?(actor)
    async_repository.then do |repository|
      next false unless repository.present?

      # Avoid the authzd request if this repo is public, since we know it'll be visible
      if repository.public?
        # Normally authzd checks if the repo has_discussions turned on; since we're
        # skipping authzd here for speed, need to check ourselves:
        next repository.async_discussions_on?
      end

      repository.async_owner.then do
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :read_discussion,
          actor: actor,
          subject: self,
        ).then do |decision|
          decision.allow?
        end
      end
    end
  end

  # Public: Can this actor create or remove a reaction from this Discussion?
  #
  # actor - A User or Bot.
  # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
  #   check will be performed asynchronously during this call; if `true` or `false` are specified, the interaction
  #   check will be skipped and the provided value will be used instead.
  #
  # Return a Promise that resolves to true or false.
  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def async_reactable_by?(actor, interaction_allowed: nil)
    DiscussionReaction.async_viewer_can_react?(actor, self, interaction_allowed: interaction_allowed)
  end

  alias_method :async_viewer_can_react?, :async_reactable_by?

  # Public: Can this actor edit the labels assigned to this Discussion?
  #
  # actor - a User or Bot
  #
  # Returns true or false.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def labelable_by?(actor)
    # For compatibility with Issue.labelable_by?, which accepts "actor" as a keyword argument
    actor = actor[:actor] if actor.is_a?(Hash)
    return false unless actor.present?

    response = ::Permissions::Enforcer.authorize(
      action: :add_label,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  # Public: Can this actor edit the labels assigned to this Discussion, determined asynchronously?
  #
  # actor - a User or Bot
  #
  # Returns a Promise that resolves to true or false.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_labelable_by?(actor)
    # For compatibility with Issue#async_labelable_by?, which accepts `actor` as a keyword argument.
    actor = actor[:actor] if actor.is_a?(Hash)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :add_label,
      actor: actor,
      subject: self,
    ).then(&:allow?)
  end

  # Public: Indicates if an actor has access to vote in a discussion's poll, if one exists. This only checks if the
  #         user is authorized to vote at all, and does not consider if they have already voted.
  #
  # actor - The User to check.
  # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
  #                       check will be performed asynchronously during this call; if `true` or `false` are specified,
  #                       the interaction check will be skipped and the provided value will be used instead.
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def poll_votable_by?(actor, interaction_allowed: nil)
    async_poll_votable_by?(actor, interaction_allowed: interaction_allowed).sync
  end

  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def async_poll_votable_by?(actor, interaction_allowed: nil)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(false) if actor.spammy? || actor.suspended? || actor.must_verify_email?

    # We reuse the same authorization logic that we use for reacting to a post. This is a pattern that we've previously
    # used in methods like `Votable#async_upvotable_by?`.
    async_reactable_by?(actor, interaction_allowed: interaction_allowed)
  end

  sig { returns(T.untyped) }
  def update_comment_count
    update(
      comment_count: comments.not_spammy.count,
      direct_comment_count: comments.not_spammy.top_level.count
    )
  end

  # Public: Returns the ID of the user who answered this discussion, if any,
  # and only if the discussion is in a category that supports marking answers.
  sig { returns(T.untyped) }
  def answered_by_id
    return unless answered?
    chosen_comment = T.must_because(self.chosen_comment) { "#answered? ensures chosen_comment is non-nil" }
    chosen_comment.user_id
  end

  sig { returns T.nilable(T::Boolean) }
  def verified?
    verified_at.present?
  end

  sig { returns T.nilable(T::Boolean) }
  def answered?
    async_answered?.sync
  end

  sig { returns Promise[T.nilable(T::Boolean)] }
  def async_answered?
    return Promise.resolve(T.let(nil, T.nilable(T::Boolean))) unless supports_mark_as_answer?
    return Promise.resolve(T.let(false, T.nilable(T::Boolean))) unless chosen_comment_id.present?

    async_chosen_comment.then do |chosen_comment|
      next false unless chosen_comment.present?

      async_category.then do |category|
        T.must(category).supports_mark_as_answer?
      end
    end
  end

  sig { returns T::Boolean }
  def unanswered?
    chosen_comment_id.nil? && supports_mark_as_answer?
  end

  sig { params(viewer: T.untyped).returns(T.untyped) }
  def latest_comment_for(viewer)
    comments.filter_spam_for(viewer).last
  end

  sig { returns(T.untyped) }
  def websocket_channel
    GitHub::WebSocket::Channels.discussion(self)
  end

  sig { returns(T.untyped) }
  def summary_websocket_channel
    GitHub::WebSocket::Channels.discussion_summary(self)
  end

  sig { returns(T.untyped) }
  def websocket_timeline_channel
    GitHub::WebSocket::Channels.discussion_timeline(self)
  end

  # Internal: Notify subscribers that the discussion has been updated.
  #
  # Returns Set of channel id Strings that were notified.
  sig { returns(T.untyped) }
  def notify_socket_subscribers
    # If we're being deleted, no reason to notify anyone
    return unless repository
    GitHub::WebSocket.notify_discussion_channel(self, websocket_channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "discussion ##{id} updated",
      # This is a load-bearing gid: https://github.com/github/github/pull/146273/files#r438329053
      gid: global_relay_id,
    )
  end

  # Internal: Notify subscribers that content related to discussion summary has been updated.
  #
  # Returns Set of channel id Strings that were notified.
  sig { returns(T.untyped) }
  def notify_summary_socket_subscribers
    GitHub::WebSocket.notify_discussion_channel(self, summary_websocket_channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "Discussion ##{id} updated with a change relevant to summarization",
      # This is a load-bearing gid: https://github.com/github/github/pull/146273/files#r438329053
      gid: global_relay_id,
    )
  end

  sig { returns T::Boolean }
  def converted_from_issue?
    !!(issue_id.present? && converted_at.present? && !converting?)
  end

  # Public: Check if this discussion was originally a team discussion (a DiscussionPost record, also called a 'team
  # post') that has since been converted to a discussion and the conversion process is finished.
  sig { returns T::Boolean }
  def converted_from_team_discussion?
    !!(team_post_id.present? && converted_at.present? && !converting?)
  end

  sig { returns T.nilable(T.any(User, Organization)) }
  def repository_owner
    repository&.owner
  end

  sig { returns(T.nilable(String)) }
  def repository_owner_login
    repository&.owner_display_login
  end

  sig { returns(String) }
  def author_display_login
    author.display_login
  end

  # Public: Is this a nested comment? No, it's not a discussion comment at all! This method exists to provide a
  # consistent interface for convenience, so that you can ask either a discussion or its comment if it's nested.
  sig { returns T::Boolean }
  def nested?
    false
  end

  sig { returns(T.untyped) }
  def reaction_groups
    async_reaction_groups.sync
  end

  sig { returns(T.untyped) }
  def async_reaction_groups
    Platform::Loaders::DiscussionReactionGroups.load(self)
  end

  sig { params(actor: T.untyped, content: T.untyped).returns(T.untyped) }
  def react(actor:, content:)
    DiscussionReaction.react(user: actor, discussion_id: id, content: content)
  end

  sig { params(actor: T.untyped, content: T.untyped).returns(T.untyped) }
  def unreact(actor:, content:)
    DiscussionReaction.unreact(user: actor, discussion_id: id, content: content)
  end

  # Public: Returns false because Discussions can't be created via email
  sig { returns FalseClass }
  def created_via_email?
    false
  end

  # Public: Return the answer associated with this Discussion, but only if it currently belongs to a DiscussionCategory
  # that supports marking answers.
  sig { returns Promise[T.nilable(DiscussionComment)] }
  def async_active_chosen_comment
    async_category.then do |category|
      next nil unless T.must(category).supports_mark_as_answer?

      async_chosen_comment
    end
  end

  # Public: Returns the User who marked the answer, or nil if unknown/not answered.
  sig { returns T.nilable(User) }
  def chosen_comment_selected_by_user
    async_chosen_comment_selected_by_user.sync
  end

  # Public: Async form of #chosen_comment_selected_by_user.
  sig { returns(T.untyped) }
  def async_chosen_comment_selected_by_user
    async_answered?.then do |answered|
      next nil unless answered

      Platform::Loaders::LatestAnsweredDiscussionEvent.load(self).then { |event| event&.async_actor }
    end
  end

  # Public: Returns the User who verified the answer, or nil if unknown/not verified.
  sig { returns T.nilable(User) }
  def chosen_comment_verified_by_user
    # For now we only support verified answers in UI so we don't need an async loader for fetching the verifying user.
    events.reorder(id: :desc).find_by(event_type: :answer_verified)&.actor
  end


  # Public: Fetch the timestamp at which the current chosen comment was selected as the answer, or nil if there is no
  # currently chosen answer.
  #
  # Returns a Promise that resolves to nil or a Date.
  sig { returns(T.untyped) }
  def async_chosen_comment_selected_at
    async_answered?.then do |answered|
      next nil unless answered

      Platform::Loaders::LatestAnsweredDiscussionEvent.load(self).then { |event| event&.created_at }
    end
  end

  # Public: Provides a method needed when referencing a discussion from a
  # comment
  # Related issue: https://github.com/github/discussions/issues/503
  sig { params(user: T.untyped, commit_id: T.untyped, repository: T.untyped).returns(T.untyped) }
  def reference_from_commit(user, commit_id, repository = nil)
  end

  # Public: Return true if the category that this discussion currently belongs to supports answer-marking
  # functionality.
  sig { returns(T.untyped) }
  def supports_mark_as_answer?
    async_supports_mark_as_answer?.sync
  end

  # Public: Async flavor of #supports_mark_as_answer?
  #
  # Returns a Promise that resolves to a boolean.
  sig { returns(T.untyped) }
  def async_supports_mark_as_answer?
    async_category.then do |category|
      next false unless category
      category.supports_mark_as_answer?
    end
  end

  # Public: Return true if the category that this discussion currently belongs to supports announcement
  # functionality.
  sig { returns(T.untyped) }
  def supports_announcements?
    async_supports_announcements?.sync
  end

  # Public: Async flavor of #supports_announcements?
  #
  # Returns a Promise that resolves to a boolean.
  sig { returns(T.untyped) }
  def async_supports_announcements?
    async_category.then do |category|
      next false unless category
      category.supports_announcements?
    end
  end

  # Public: Return true if the category that this discussion currently belongs to supports polls
  # functionality.
  sig { returns(T.untyped) }
  def supports_polls?
    async_supports_polls?.sync
  end

  # Public: Async flavor of #supports_polls?
  #
  # Returns a Promise that resolves to a boolean.
  sig { returns(T.untyped) }
  def async_supports_polls?
    async_category.then do |category|
      next false unless category
      category.supports_polls?
    end
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  sig { returns(T.untyped) }
  def safe_user
    user || User.ghost
  end

  # Public: Compatibility with Issue in some GraphQL mutations. We don't currently mark DiscussionEvents as
  # App-authored, so we can ignore this.
  sig { params(_: T.untyped).returns(T.untyped) }
  def modifying_integration=(_)
    # Ignore
    nil
  end

  sig { returns(T.untyped) }
  def og_image_url
    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        updated_at,
        repository&.name,
        repository&.owner_id,
      ]
    )
    open_graph.og_image_url
  end

  sig { returns(T.untyped) }
  def template
    category&.template
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

  sig { returns(T.untyped) }
  def dom_id
    return unless persisted?
    "discussion-#{id}"
  end

  sig { returns(T.untyped) }
  def permalink_id
    return unless persisted?
    "#{dom_id}-permalink"
  end

  sig { returns(T.untyped) }
  def discussion_format
    category = self.category
    return :DISCUSSION_FORMAT_UNKNOWN if category.nil?

    if category.supports_mark_as_answer?
      discussion_format = :DISCUSSION_FORMAT_QUESTION_ANSWER
    elsif category.supports_polls?
      discussion_format = :DISCUSSION_FORMAT_POLL
    elsif category.supports_announcements?
      discussion_format = :DISCUSSION_FORMAT_ANNOUNCEMENT
    else
      discussion_format = :DISCUSSION_FORMAT_OPEN_ENDED
    end

    discussion_format
  end

  # Public: The state value for Hydro.
  sig { returns(T.untyped) }
  def discussion_state
    :"STATE_#{state.upcase}"
  end

  # Public: The state reason value for Hydro.
  sig { returns(T.untyped) }
  def discussion_state_reason
    state_reason = self.state_reason
    return :STATE_REASON_UNKNOWN unless state_reason.present?
    :"STATE_REASON_#{state_reason.upcase}"
  end

  # Public: A discussion with ids for a repository or discussion category that no longer exists is considered an orphaned discussion
  sig { returns(T.untyped) }
  def orphaned?
    if repository && category
      false
    else
      true
    end
  end

  private

  def filter_issue_events_for_repo_without_issues(events)
    return events if repository&.has_issues?
    events.reject { |event| event.created_issue? }
  end

  def user_has_verified_email
    user = self.user
    return unless user

    # The Bot user associated with a GitHub App never has a verified email.
    return if user.bot?

    # If we're converting an existing issue to a discussion, don't require the issue to have
    # been created by a user with a verified email address.
    return unless open?

    if user.should_verify_email?
      errors.add(:user, "must have a verified email address")
    end
  end

  def category_is_not_deleting
    category = self.category
    return unless category

    if category.deleting?
      errors.add(:category, "is being deleted")
    end
  end

  def category_belongs_to_same_repo
    category = self.category
    return unless category

    if category.repository_id != repository_id
      errors.add(:category, "must belong to the same repository")
    end
  end

  def category_is_accessible
    # If this is a new record, we should use the author, unless it is being converted from an issue. Otherwise, use the
    # `actor` that is set anywhere where we edit a discussion.
    category_actor = (new_record? && !converting?) ? user : actor

    if category&.supports_announcements?
      if !repository&.can_create_discussion_announcements?(category_actor)
        errors.add(:category, "is not accessible to the actor")
      end
    end
  end

  def cannot_change_poll_discussion_category
    # If a discussion has a poll, users cannot change to a category that doesn't support polls.
    previous_category_id, new_category_id = discussion_category_id_change
    previous_category = DiscussionCategory.find_by(id: previous_category_id)

    return unless previous_category && previous_category.supports_polls?

    new_category = DiscussionCategory.find(T.must(new_category_id))

    errors.add(:category, "cannot change a poll's category") unless new_category.supports_polls?
  end

  def cannot_change_to_poll_discussion_category
    # If a discussion has a poll, users cannot change to a category that doesn't support polls.
    previous_category_id, new_category_id = discussion_category_id_change
    previous_category = DiscussionCategory.find_by(id: previous_category_id)

    return unless previous_category && !previous_category.supports_polls?

    new_category = DiscussionCategory.find(T.must(new_category_id))

    errors.add(:category, "cannot change a non-poll discussion category to a poll supporting category") if new_category.supports_polls?
  end

  # Private: Set the plan number to the next sequence for this listing
  def set_number!
    return unless repository
    Sequence.create(repository) unless Sequence.exists?(repository)
    self[:number] ||= Sequence.next(repository)
  end

  def strip_title
    self.title = title&.strip
  end

  def ensure_author_is_not_blocked
    repository = self.repository
    return unless user && repository

    # Allow transferring a discussion to another repository even if the author
    # is blocked by the new repo owner
    return if transferring?

    if repository.owner_blocking?(user)
      errors.add :user, "cannot post at this time"
    end
  end

  def discussion_is_question_if_chosen_comment_set
    return unless answered?

    unless supports_mark_as_answer?
      errors.add(:chosen_comment, "cannot be specified for a non-question discussion")
    end
  end

  def user_exists_when_open_state
    if open? && user.nil?
      errors.add(:user, "can't be blank")
    end
  end

  def chosen_comment_matches_discussion
    return if new_record?

    chosen_comment = self.chosen_comment
    return if chosen_comment.nil?

    unless chosen_comment.discussion_id == id
      errors.add(:chosen_comment, "is not for this discussion")
    end
  end

  def issue_or_team_discussion_present_if_converting
    return unless converting?

    if !issue && !team_discussion # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      # just add the error on the issue for now rather than adding to both
      errors.add(:issue, "must be specified if state = converting")
    end
  end

  def error_reason_present_if_error
    return unless error?

    if error_reason.nil? || no_error?
      errors.add(:error_reason, "must be specified when state = error")
    end
  end

  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion.create", {
      actor: user,
      discussion: self
    }

    message_v2 = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      # if a discussion is created, or converted from an issue, by a "ghost user",
      # the discussion will have no actor, so use the safe_actor method
      actor_id: safe_user&.id,
      actor: safe_user,
      discussion_id: self.id,
      discussion: self,
      # discussions are unlocked by default / upon creation,
      # except when they are converted from an issue that is also locked.
      lock_status: locked? ? :LOCK_STATUS_LOCKED : :LOCK_STATUS_UNLOCKED,
      # discussions are unpinned by default / upon creation.
      # they are in the spotlight if they are pinned.
      pin_status: spotlight ? :PIN_STATUS_PINNED : :PIN_STATUS_UNPINNED,
      announcement: supports_announcements? ? true : false,
      org_or_repo_level: organization_discussion? ? :ORG_OR_REPO_LEVEL_ORG : :ORG_OR_REPO_LEVEL_REPO,
      action: :ACTION_DISCUSSION_CREATED,
      action_timestamp: Time.now,
      # formats: q&a, poll, announcement, open ended
      discussion_format: discussion_format,
      category_id: discussion_category_id,
      converted_from_issue: converted_from_issue?,
      converted_issue_id: issue_id,
      created_from_category_template: created_from_category_template,
      state: discussion_state,
      state_reason: discussion_state_reason,
    }
    GlobalInstrumenter.instrument "discussions", message_v2

    instrument :create
  end

  def instrument_update_event
    previous_body = previous_changes.dig(:body, 0)
    previous_category_id, _ = previous_changes[:discussion_category_id]
    previous_category =
      (previous_category_id && repository&.discussion_categories&.find_by(id: previous_category_id)) ||
      category

    GlobalInstrumenter.instrument "discussion.update", {
      discussion: self,
      previous_category: previous_category,
      previous_body: previous_body,
      actor: actor || editor
    }

    message_v2 = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      # if a discussion is created, or converted from an issue, by a "ghost user",
      # the discussion will have no actor, so use the safe_actor method
      actor_id: safe_actor&.id,
      actor: safe_actor,
      discussion_id: self.id,
      discussion: self,
      # discussions are unlocked by default / upon creation,
      # except when they are converted from an issue that is also locked.
      lock_status: locked? ? :LOCK_STATUS_LOCKED : :LOCK_STATUS_UNLOCKED,
      # discussions are unpinned by default / upon creation.
      # they are in the spotlight if they are pinned.
      pin_status: spotlight ? :PIN_STATUS_PINNED : :PIN_STATUS_UNPINNED,
      announcement: supports_announcements? ? true : false,
      org_or_repo_level: organization_discussion? ? :ORG_OR_REPO_LEVEL_ORG : :ORG_OR_REPO_LEVEL_REPO,
      action: :ACTION_DISCUSSION_UPDATED,
      action_timestamp: Time.now,
      # formats: q&a, poll, announcement, open ended
      discussion_format: discussion_format,
      category_id: discussion_category_id,
      converted_from_issue: converted_from_issue?,
      converted_issue_id: issue_id,
      state: discussion_state,
      state_reason: discussion_state_reason,
    }

    GlobalInstrumenter.instrument "discussions", message_v2

    if previous_category_id
      instrument :category_change, old_category_id: previous_category_id, actor: actor
    end
  end

  def instrument_publish_event
    scheduled_to_open = saved_change_to_state?(from: "scheduled", to: "open")
    draft_to_open = saved_change_to_state?(from: "draft", to: "open")

    return unless scheduled_to_open || draft_to_open

    GlobalInstrumenter.instrument("discussions_publish", {
      discussion: self,
      action: scheduled_to_open ? :SCHEDULED_PUBLISHED : :DRAFT_PUBLISHED,
      action_timestamp: Time.current,
    })
  end

  def audit_log_update_event
    old_title, _ = previous_changes[:title]
    old_body, _ = previous_changes[:body]

    payload = {}.tap do |p|
      p[:actor] = actor if actor
      p[:old_title] = old_title if old_title
      p[:old_body] = old_body if old_body
    end

    instrument :update, payload
  end

  # we need to generate the payload before the discussion is deleted, so we don't lose the data
  def generate_webhook_payload
    if !actor || actor&.spammy?
      @delivery_system = nil
      return
    end

    event = Hook::Event::DiscussionEvent.new(
      discussion_id: self.id,
      action: deletion_hook_action || :deleted,
      actor_id: actor&.id,
      triggered_at: Time.now
    )
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def instrument_deletion_event
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload` must be called before `instrument_destruction`"
    end

    @delivery_system&.deliver_later
    instrument :destroy

    GlobalInstrumenter.instrument "discussion.delete", discussion: self,
      actor: actor

    message_v2 = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      # if a discussion is created, or converted from an issue, by a "ghost user",
      # the discussion will have no actor, so use the safe_actor method
      actor_id: safe_actor&.id,
      actor: safe_actor,
      discussion_id: self.id,
      discussion: self,
      # discussions are unlocked by default / upon creation,
      # except when they are converted from an issue that is also locked.
      lock_status: locked? ? :LOCK_STATUS_LOCKED : :LOCK_STATUS_UNLOCKED,
      # discussions are unpinned by default / upon creation.
      # they are in the spotlight if they are pinned.
      pin_status: spotlight ? :PIN_STATUS_PINNED : :PIN_STATUS_UNPINNED,
      announcement: supports_announcements? ? true : false,
      org_or_repo_level: organization_discussion? ? :ORG_OR_REPO_LEVEL_ORG : :ORG_OR_REPO_LEVEL_REPO,
      action: :ACTION_DISCUSSION_DELETED,
      action_timestamp: Time.now,
      # formats: q&a, poll, announcement, open ended
      discussion_format: discussion_format,
      category_id: discussion_category_id,
      converted_from_issue: converted_from_issue?,
      converted_issue_id: issue_id,
      state: discussion_state,
      state_reason: discussion_state_reason,
    }

    GlobalInstrumenter.instrument "discussions", message_v2
  end

  def event_prefix() :discussion end

  def event_payload
    payload = {
      event_prefix   => self,
      :title         => title,
      :body          => body,
      :user          => user,
      :number        => number,
      :comment_count => comment_count,
      :issue_id      => issue_id,
      :converted_at  => converted_at,
    }

    repository = self.repository
    if repository
      payload[repository.event_prefix] = repository

      if org = repository.organization
        payload[org.event_prefix] = org
      end
    end

    category = self.category
    if category
      payload[category.event_prefix] = category
    end

    payload
  end

  def maybe_bump_on_changes
    # Bump if body was changed or if the comment_count _increased_
    comment_count_increased = if changes.key?(:comment_count)
      before, after = changes[:comment_count]
      after > before
    end

    if body_changed? || comment_count_increased
      bump
    end
  end

  def initial_bump
    if !bumped_at
      bump
    end
  end

  def bump
    self.bumped_at = Time.current
  end

  def create_initial_upvote
    DiscussionVote.create(discussion: self, user: user, upvote: true)
  end

  def count_daily_contributors
    created_at = self.created_at || Time.current
    CommunityInsights::DiscussionsDailyContributorsJob.perform_later(repository_id, created_at.to_date)
  end

  def notify_socket_subscribers_for_chosen_comment
    previous_changes[:chosen_comment_id].compact.each do |comment_id|
      comments.find_by(id: comment_id)&.notify_socket_subscribers
    end
  end

  def safe_actor
    @actor ||= (self.actor || User.ghost)
  end

  def body_can_be_empty?
    converting? || category&.supports_polls?
  end

  def destroy_category_pin
    category_pin = self.category_pin
    category_pin.destroy if category_pin
  end

  def saved_reply_copy_target
    self.repository
  end

  def reject_indexing?
    orphaned? || user.nil? || user&.spammy?
  end
end
