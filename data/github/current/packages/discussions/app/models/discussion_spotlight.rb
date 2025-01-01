# typed: true
# frozen_string_literal: true

class DiscussionSpotlight < ApplicationRecord::Domain::Discussions
  include GitHub::Validations

  # These are the color stops for the (light mode) gradients used by repositories in the :discussions_next_layout
  # feature.
  RED_ORANGE_COLOR_STOPS = %w[FF7B72 F0883E]
  BLUE_MINT_COLOR_STOPS = %w[58A6FF 56D364]
  BLUE_PURPLE_COLOR_STOPS = %w[58A6FF BC8CFF]
  PINK_BLUE_COLOR_STOPS = %w[F778BA 58A6FF]
  PURPLE_CORAL_COLOR_STOPS = %w[BC8CFF FF7B72]

  # Maps existing enum values of the preconfigured_color field to the color stops that should be used by repositories
  # in the :discussions_next_layout feature. Note that multiple preconfigured_color values map to the same gradient.
  NEXT_PRECONFIGURED_COLOR_STOPS = {
    peach_red: RED_ORANGE_COLOR_STOPS,
    orange_magenta: RED_ORANGE_COLOR_STOPS,
    gold_red: RED_ORANGE_COLOR_STOPS,
    green: BLUE_MINT_COLOR_STOPS,
    teal: BLUE_MINT_COLOR_STOPS,
    cyan_purple: BLUE_PURPLE_COLOR_STOPS,
    periwinkle_navy: BLUE_PURPLE_COLOR_STOPS,
    purple_navy: BLUE_PURPLE_COLOR_STOPS,
    purple: PINK_BLUE_COLOR_STOPS,
    salmon_purple: PINK_BLUE_COLOR_STOPS,
    fuchsia_purple: PURPLE_CORAL_COLOR_STOPS,
    gray: PURPLE_CORAL_COLOR_STOPS,
  }.freeze

  # The subset of preconfigured_color enum values that are valid in :discussions_next_layout. This is one enum value
  # of each set that maps to a unique next-layout gradient value.
  NEXT_PRECONFIGURED_COLORS = T.let(%w(peach_red green cyan_purple purple gray).freeze, T::Array[String])

  # Names of the :discussions_next_layout gradients. These are *not* (yet) valid values for preconfigured_color to
  # assume. They should be used instead of using preconfigured_color values directly in user-visible places like the
  # API.
  NEXT_GRADIENT_NAMES = T.let(%w(red_orange blue_mint blue_purple pink_blue purple_coral).freeze, T::Array[String])

  # Map existing preconfigured_color enum values to the descriptive next-layout names.
  PRECONFIGURED_TO_NEXT = {
    peach_red: :red_orange,
    orange_magenta: :red_orange,
    gold_red: :red_orange,
    green: :blue_mint,
    teal: :blue_mint,
    cyan_purple: :blue_purple,
    periwinkle_navy: :blue_purple,
    purple_navy: :blue_purple,
    purple: :pink_blue,
    salmon_purple: :pink_blue,
    fuchsia_purple: :purple_coral,
    gray: :purple_coral,
  }.freeze

  COLOR_REGEXP = /\A[0-9a-f]{6}\z/iu # e.g., ff00ff
  COLOR_SHORTHAND_REGEXP = /\A[0-9a-f]{3}\z/iu # e.g., fff

  LIMIT_PER_REPOSITORY = 4

  belongs_to :repository, required: true
  belongs_to :spotlighted_by, class_name: "User"
  belongs_to :discussion, required: true

  has_one :category, through: :discussion

  before_validation :set_repository
  before_validation :expand_custom_color_shorthand
  before_validation :set_position, on: :create

  enum :preconfigured_color, {
    peach_red: 0,
    orange_magenta: 1,
    gold_red: 2,
    green: 3,
    teal: 4,
    cyan_purple: 5,
    periwinkle_navy: 6,
    purple_navy: 7,
    purple: 8,
    salmon_purple: 9,
    fuchsia_purple: 10,
    gray: 11,
  }

  enum :pattern, {
    "dot-fill": 0,
    "plus": 1,
    "zap": 2,
    "chevron-up": 3,
    "dot": 4,
    "heart-fill": 5
  }

  validates :spotlighted_by, presence: true, on: :create
  validates :discussion, uniqueness: { scope: :repository_id }
  validates :position, presence: true,
            numericality: { only_integer: true, greater_than: 0, less_than: 128 },
            uniqueness: { scope: :repository_id }
  validates :other_repo_spotlights_count, numericality: { less_than: :repo_spotlight_limit }
  validates_format_of :custom_color, allow_blank: true, with: COLOR_REGEXP
  validate :ensure_at_least_one_color_option_set

  # Webhooks
  after_commit :instrument_creation_event, on: :create
  after_destroy_commit :instrument_deletion_event

  scope :for_discussion, ->(discussion) { where(discussion_id: discussion) }
  scope :for_repository, ->(repo) { where(repository_id: repo) }

  # For attribution in the deletion callback
  attr_accessor :actor

  # Public: Returns a list of valid preconfigured color options for a spotlight's background.
  sig { returns T::Array[String] }
  def self.preconfigured_color_names
    NEXT_PRECONFIGURED_COLORS
  end

  # Public: Returns a list of valid pattern options for a spotlight's background.
  sig { returns(T.untyped) }
  def self.pattern_names
    patterns.keys
  end

  # Public: Returns a list of two HTML color codes representing the gradient color stops for the
  # given preconfigured color option, to style the spotlight's background.
  sig { params(preconfigured_color: T.untyped).returns(T.untyped) }
  def self.color_stops_for(preconfigured_color)
    NEXT_PRECONFIGURED_COLOR_STOPS[preconfigured_color.to_sym]
  end

  sig { returns(T.untyped) }
  def color_stops
    self.class.color_stops_for(preconfigured_color)
  end

  # Public: Return the next-layout color corresponding to the current preconfigured gradient.
  #
  # Once the next_layout is fully rolled out and we have no old preconfigured_color values in the database, remove this
  # and use #preconfigured_color directly in the API.
  #
  # Returns a String from the NEXT_PRECONFIGURED_COLORS set.
  sig { returns T.nilable(String) }
  def api_preconfigured_color
    preconfigured_color = self.preconfigured_color
    return nil unless preconfigured_color
    PRECONFIGURED_TO_NEXT[preconfigured_color.to_sym].to_s
  end

  # Public: Is the given repository already at the limit for how many discussion spotlights
  # it can have?
  sig { params(repo: Repository).returns(T::Boolean) }
  def self.repository_at_limit?(repo)
    # Uses size instead of count to load/reuse the association for later use
    repo.discussion_spotlights.size >= LIMIT_PER_REPOSITORY
  end

  sig { returns T.nilable(User) }
  def discussion_author
    discussion&.author
  end

  # Public: Returns the other DiscussionSpotlights for this repository, excluding this one.
  sig { returns(T.untyped) }
  def other_repo_spotlights
    repository = self.repository
    return DiscussionSpotlight.none unless repository
    repository.discussion_spotlights.where.not(id: id)
  end

  # Public: Returns the count of discussion spotlights the repository has other than this one.
  sig { returns Integer }
  def other_repo_spotlights_count
    other_repo_spotlights.count
  end

  # Public: Type name used by the GraphQL API.
  sig { returns String }
  def platform_type_name
    "PinnedDiscussion"
  end

  private

  # Private: Expands colors of three character length `"000"`
  # into six character hex code `"000000"`.
  sig { void }
  def expand_custom_color_shorthand
    self.custom_color = Labelable.expand_color_shorthand(self.custom_color)
  end

  sig { void }
  def set_repository
    self.repository = discussion&.repository
  end

  sig { returns Integer }
  def repo_spotlight_limit
    return 1 unless repository
    LIMIT_PER_REPOSITORY
  end

  sig { void }
  def ensure_at_least_one_color_option_set
    if preconfigured_color.blank? && custom_color.blank?
      errors.add(:base, "Either a preconfigured color or a custom color must be set.")
    end
  end

  sig { void }
  def set_position
    max_position = other_repo_spotlights.maximum(:position) || 0

    # we only overwrite position if this object's position is the default, 1
    if position == 1
      self.position = max_position + 1
    end
  end

  sig { void }
  def instrument_creation_event
    safe_actor = spotlighted_by || User.ghost

    # Webhooks
    GitHub.instrument "discussion.pin", action: :pinned, actor: safe_actor, discussion: discussion

    # Hydro
    GlobalInstrumenter.instrument "discussion.pin", actor: safe_actor, discussion: discussion

    message_v2 = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      # if a discussion is created, or converted from an issue, by a "ghost user",
      # the discussion will have no actor, so use the safe_actor method
      actor_id: safe_actor&.id,
      actor: safe_actor,
      discussion_id: discussion&.id,
      discussion: discussion,
      # discussions are unlocked by default / upon creation,
      # except when they are converted from an issue that is also locked.
      lock_status: discussion&.locked? ? :LOCK_STATUS_LOCKED : :LOCK_STATUS_UNLOCKED,
      # discussions are unpinned by default / upon creation.
      # they are in the spotlight if they are pinned.
      pin_status: :PIN_STATUS_PINNED,
      announcement: discussion&.supports_announcements? ? true : false,
      org_or_repo_level: discussion&.organization_discussion? ? :ORG_OR_REPO_LEVEL_ORG : :ORG_OR_REPO_LEVEL_REPO,
      action: :ACTION_DISCUSSION_UPDATED,
      action_timestamp: Time.now,
      # formats: q&a, poll, announcement, open ended
      discussion_format: discussion&.discussion_format,
      category_id: discussion&.discussion_category_id,
      converted_from_issue: discussion&.converted_from_issue? ? true : false,
      converted_issue_id: discussion&.converted_from_issue? ? discussion&.issue_id : nil,
      state: discussion&.discussion_state,
      state_reason: discussion&.discussion_state_reason,
    }
    GlobalInstrumenter.instrument "discussions", message_v2

  end

  sig { void }
  def instrument_deletion_event
    safe_actor = actor || User.ghost

    # Webhooks
    GitHub.instrument "discussion.unpin", action: :unpinned, actor: safe_actor, discussion: discussion

    # Hydro
    GlobalInstrumenter.instrument "discussion.unpin", actor: safe_actor, discussion: discussion
    message_v2 = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      # if a discussion is created, or converted from an issue, by a "ghost user",
      # the discussion will have no actor, so use the safe_actor method
      actor_id: safe_actor&.id,
      actor: safe_actor,
      discussion_id: discussion&.id,
      discussion: discussion,
      # discussions are unlocked by default / upon creation,
      # except when they are converted from an issue that is also locked.
      lock_status: discussion&.locked? ? :LOCK_STATUS_LOCKED : :LOCK_STATUS_UNLOCKED,
      # discussions are unpinned by default / upon creation.
      # they are in the spotlight if they are pinned.
      pin_status: :PIN_STATUS_UNPINNED,
      announcement: discussion&.supports_announcements? ? true : false,
      org_or_repo_level: discussion&.organization_discussion? ? :ORG_OR_REPO_LEVEL_ORG : :ORG_OR_REPO_LEVEL_REPO,
      action: :ACTION_DISCUSSION_UPDATED,
      action_timestamp: Time.now,
      # formats: q&a, poll, announcement, open ended
      discussion_format: discussion&.discussion_format,
      category_id: discussion&.discussion_category_id,
      converted_from_issue: discussion&.converted_from_issue? ? true : false,
      converted_issue_id: discussion&.converted_from_issue? ? discussion&.issue_id : nil,
      state: discussion&.discussion_state,
      state_reason: discussion&.discussion_state_reason,
    }
    GlobalInstrumenter.instrument "discussions", message_v2
  end
end
