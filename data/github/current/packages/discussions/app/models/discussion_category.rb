# typed: true
# frozen_string_literal: true

class DiscussionCategory < ApplicationRecord::Domain::Discussions
  MAX_CATEGORIES_PER_REPO = 25

  ANNOUNCEMENTS_NAME = "Announcements"
  GENERAL_NAME = "General"
  include GitHub::Validations
  include GitHub::UTF8
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::DiscussionCategory

  attribute :emoji, StringFromBinary.new
  attribute :name, StringFromBinary.new
  attribute :description, StringFromBinary.new

  belongs_to :repository, required: true
  has_many :discussions
  belongs_to :discussion_section, required: false

  # Transient state used to control Hydro events
  attr_accessor :actor, :seeding

  validates :name, presence: true, unicode: true
  validates :slug, uniqueness: { scope: :repository_id, case_sensitive: false }
  validates :emoji, presence: true, single_emoji: true, unicode: true,
    allowed_emoji: true, unless: :seeding?
  validates :description, unicode: true
  validate :ensure_count_per_repository, on: :create

  before_validation :strip_name
  before_validation :generate_slug, if: :name_changed?

  # Hydro telemetry and audit logs
  after_commit :instrument_creation_event, on: :create, unless: :seeding?
  after_commit :instrument_update_event, on: :update, if: -> do
    T.bind(self, DiscussionCategory)
    previous_changes.present?
  end
  after_destroy_commit :instrument_deletion_event

  sig { returns T.nilable(String) }
  def to_s
    name
  end

  # Public: Return a list of DiscussionCategory attributes used to create
  # initial categories when discussions are first enabled on a Repository.
  #
  # An Array of DiscussionCategory attributes in Hash form.
  sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
  def self.initial_categories
    [
      {
        name: ANNOUNCEMENTS_NAME,
        description: "Updates from maintainers",
        emoji: ":mega:",
        supports_mark_as_answer: false,
        supports_announcements: true,
        supports_polls: false,
        seeding: true,
      },
      {
        name: GENERAL_NAME,
        description: "Chat about anything and everything here",
        emoji: ":speech_balloon:",
        supports_mark_as_answer: false,
        supports_announcements: false,
        supports_polls: false,
        seeding: true,
      },
      {
        name: "Q&A",
        description: "Ask the community for help",
        emoji: ":pray:",
        supports_mark_as_answer: true,
        supports_announcements: false,
        supports_polls: false,
        seeding: true,
      },
      {
        name: "Ideas",
        description: "Share ideas for new features",
        emoji: ":bulb:",
        supports_mark_as_answer: false,
        supports_announcements: false,
        supports_polls: false,
        seeding: true,
      },
      {
        name: "Show and tell",
        description: "Show off something you've made",
        emoji: ":raised_hands:",
        supports_mark_as_answer: false,
        supports_announcements: false,
        supports_polls: false,
        seeding: true,
      },
      {
        name: "Polls",
        description: "Take a vote from the community",
        emoji: ":ballot_box:",
        supports_mark_as_answer: false,
        supports_announcements: false,
        supports_polls: true,
        seeding: true,
      }
    ]
  end

  TEAM_POST_MIGRATION_CATEGORY = {
    name: "Team Posts",
    description: "Migrated from Team Posts",
    emoji: ":speech_balloon:",
    supports_mark_as_answer: false,
    supports_announcements: false,
    supports_polls: false
  }
  COMPATIBLE_EXISTING_TEAM_POST_MIGRATION_CATEGORY = {
    slug: "team-posts",
    supports_mark_as_answer: false,
    supports_announcements: false,
    supports_polls: false
  }

  # Internal: Generate a Discussions::Kv.store key for in-progress deletions.
  sig { params(id: T.untyped).returns(T.untyped) }
  def self.deleting_key_for(id)
    "discussion_category_#{id}_deleting"
  end

  sig { returns(T.untyped) }
  def strip_name
    self.name = name&.strip
  rescue Encoding::CompatibilityError
  end

  # Public: Generate the URL-safe slug value corresponding to a category name.
  sig { params(name: String).returns(String) }
  def self.slug_for_name(name)
    name.downcase.gsub(/[^\p{Word}]+/, "-").chomp("-")
  end

  # Public: Access the slug for the Announcements category.
  sig { returns String }
  def self.announcements_slug
    slug_for_name(ANNOUNCEMENTS_NAME)
  end

  # Public: Access the slug for the General category.
  sig { returns String }
  def self.general_slug
    slug_for_name(GENERAL_NAME)
  end

  # Public: Can an actor view this discussion category?
  #
  # actor - a User or Bot
  #
  # Returns a boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def readable_by?(actor)
    if repository&.public?
      return T.must(repository).discussions_on?
    end

    ::Permissions::Enforcer.authorize(
      action: :read_discussion_category,
      actor: actor,
      subject: self,
    ).allow?
  end

  # Public: Can an actor view this discussion category, determined asynchronously?
  #
  # actor - a User or Bot
  #
  # Returns a Promise that resolves to a boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_readable_by?(actor)
    async_repository.then do |repository|
      # Avoid the authzd request if this repo is public.
      if T.must(repository).public?
        # Normally authzd checks if the repo has_discussions turned on; since we're
        # skipping authzd here for speed, we need to check ourselves:
        next T.unsafe(repository).async_discussions_on?
      end

      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :read_discussion_category,
        actor: actor,
        subject: self,
      ).then { |decision| decision.allow? }
    end
  end

  # Public: Returns HTML to render the emoji for this category.
  sig { returns(T.untyped) }
  def emoji_html
    context = T.let({ base_url: GitHub.url }, T::Hash[T.untyped, T.untyped])
    GitHub::Goomba::SimpleDescriptionPipeline.to_html(emoji, context)
  end

  sig { returns T.nilable(T.any(User, Organization)) }
  def repository_owner
    repository&.owner
  end

  sig { returns Symbol }
  def event_prefix() :discussion_category end

  sig { returns(T.untyped) }
  def event_payload
    payload = {
      event_prefix => self,
      :name        => name,
      :emoji       => emoji,
      :description => description,
    }

    repository = self.repository
    if repository
      payload[repository.event_prefix] = repository

      if org = repository.organization
        payload[org.event_prefix] = org
      end
    end

    payload
  end

  # Public: Is this category in the process of being deleted?
  #
  # Categories that are being deleted should not be eligible to have discussions associated with them.
  sig { returns T::Boolean }
  def deleting?
    Discussions::Kv.store.exists(deleting_key).value { false }
  end

  # Public: Are any categories in an array or a relation not being deleted?
  sig { params(categories: T.untyped).returns(T.untyped) }
  def self.any_not_deleting?(categories)
    keys = categories.pluck(:id).map { |id| deleting_key_for(id) }
    return false if keys.empty?
    Discussions::Kv.store.mget(keys).value!.any? { |result| result.nil? }
  end

  # Public: Flag a category as having a deletion in progress. This flag will time out if the record is not successfully
  # destroyed within five minutes.
  sig { void }
  def mark_as_deleting!
    Discussions::Kv.store.set(deleting_key, "", expires: 5.minutes.from_now)
  end

  # Public: Revoke a deletion in progress.
  sig { void }
  def unmark_as_deleting!
    Discussions::Kv.store.del(deleting_key)
  end

  # Public: Can the given actor delete the discussion?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def deletable_by?(actor)
    response = ::Permissions::Enforcer.authorize(
      action: :delete_discussion_category,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_deletable_by?(actor)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :delete_discussion_category,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Can the given actor change the name and emoji of this category?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def modifiable_by?(actor)
    response = ::Permissions::Enforcer.authorize(
      action: :edit_discussion_category,
      actor: actor,
      subject: self,
    )
    response.allow?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_modifiable_by?(actor)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :edit_discussion_category,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Is this category being seeded on a repository that is having the discussions feature enabled for the first
  # time?
  sig { returns(T.untyped) }
  def seeding?
    seeding
  end

  sig { returns Symbol }
  def discussion_format
    if supports_polls
      :DISCUSSION_FORMAT_POLL
    elsif supports_announcements
      :DISCUSSION_FORMAT_ANNOUNCEMENT
    elsif supports_mark_as_answer
      :DISCUSSION_FORMAT_QUESTION_ANSWER
    else
      :DISCUSSION_FORMAT_OPEN_ENDED
    end
  end

  # Public: Can this category be used as the target category for Team Posts transfer to Discussions?
  sig { returns T::Boolean }
  def compatible_for_team_posts_transfer?
    !!(slug == COMPATIBLE_EXISTING_TEAM_POST_MIGRATION_CATEGORY[:slug] && !supports_polls? && !supports_mark_as_answer? && !supports_announcements?)
  end

  # Public: The category template if it exists
  #
  # Returns a DiscussionTemplate or nil.
  sig { returns(T.nilable(DiscussionTemplate)) }
  def template
    @template ||= async_template.sync
  end

  sig { returns(Promise[T.nilable(DiscussionTemplate)]) }
  def async_template
    repository = self.repository
    return Promise.resolve(T.let(nil, T.nilable(DiscussionTemplate))) unless repository

    repository.async_preferred_discussion_templates.then do |templates|
      templates&.for_slug(slug)
    end
  end

  private

  def generate_slug
    # Necessary because this callback runs before the unicode: true validation
    # and .downcase throws an ArgumentError on invalid bytes
    return unless name.valid_encoding?

    self.slug = self.class.slug_for_name(name)
  end

  # Discussions::Kv.store key used to mark categories that are currently in the process of being deleted.
  def deleting_key
    self.class.deleting_key_for(id)
  end

  def ensure_count_per_repository
    # Don't use the repository.discussion_categories relations to avoid incorrectly cached counts and unnecessary
    # repository loading.
    category_count = self.class.where(repository_id: repository_id).size

    if category_count >= MAX_CATEGORIES_PER_REPO
      # check if there is an override that allows for more categories
      override_count = DiscussionCategory::LimitOverride.for(repository)
      return if override_count.present? && category_count <= override_count

      maximum_count = override_count.present? ? override_count : MAX_CATEGORIES_PER_REPO

      errors.add(:repository, "can only have a maximum of #{maximum_count} categories")
    end
  end

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_category.create", discussion_category: self, actor: actor

    message = {
      repository_id: repository_id,
      repository: repository,
      repository_owner: repository&.owner,
      actor_id: actor&.id,
      actor: actor,
      action: :ACTION_DISCUSSION_CREATED,
      action_timestamp: created_at,
      category_id: id,
      discussion_format: discussion_format,
      category_name: name,
      discussion_section: discussion_section&.id,
    }
    GlobalInstrumenter.instrument "discussions_category", message
  end

  sig { void }
  def instrument_update_event
    GlobalInstrumenter.instrument "discussion_category.update", discussion_category: self, actor: actor

    message = {
      repository_id: repository_id,
      repository: repository,
      repository_owner: repository&.owner,
      actor_id: actor&.id,
      actor: actor,
      action: :ACTION_DISCUSSION_UPDATED,
      action_timestamp: Time.now,
      category_id: id,
      discussion_format: discussion_format,
      category_name: name,
      discussion_section: discussion_section&.id,
    }
    GlobalInstrumenter.instrument "discussions_category", message
  end

  sig { void }
  def instrument_deletion_event
    instrument :destroy

    GlobalInstrumenter.instrument "discussion_category.delete", discussion_category: self, actor: actor

    # When a repo is destroyed, its dependent records are also destroyed. In
    # this case, the repository association will be `nil` on the
    # `DiscussionCategory` record, so we will do nothing as much of the data we
    # need via the parent repo is unavailable.
    if repository.present?
      message = {
        repository_id: repository_id,
        repository: repository,
        repository_owner: repository&.owner,
        actor_id: actor&.id,
        actor: actor,
        action: :ACTION_DISCUSSION_DELETED,
        action_timestamp: Time.now,
        category_id: id,
        discussion_format: discussion_format,
        category_name: name,
        discussion_section: discussion_section&.id,
      }
      GlobalInstrumenter.instrument "discussions_category", message
    end
  end
end
