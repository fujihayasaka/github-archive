# typed: true
# frozen_string_literal: true

class DiscussionReaction < ApplicationRecord::Domain::Discussions
  include GitHub::Relay::GlobalIdentification
  include Spam::Spammable
  include InteractionBanValidation

  belongs_to :user, required: true
  belongs_to :discussion, required: true

  sig { returns Promise[T.nilable(Discussion)] }
  def async_subject
    async_discussion
  end

  setup_spammable(:user)

  validates :content, inclusion: { in: Emotion.all.map(&:content) }
  validate :user_can_interact, on: :create

  delegate :repository, to: :discussion, allow_nil: true

  # Hydro instrumentation
  after_commit :instrument_creation_event, on: :create
  after_destroy_commit :instrument_deletion_event

  # Community Insights data
  after_commit :count_daily_contributors, on: [:create, :destroy]

  class << self
    # Public: Idempotent all-purpose interface for ensuring a discussion reaction
    # exists between users and discussions.
    # Performs permissions checks and prevents duplicates.
    #
    # user          - User: The user having this reaction
    # discussion_id - Integer: The ID of the discussion of this reaction
    # content       - String: One of the members of Emotion.all.map(&:content)
    #
    # Returns: A DiscussionReaction in the appropriate state for the discussion
    # and user.
    sig { params(user: T.untyped, discussion_id: T.untyped, content: T.untyped).returns(T.untyped) }
    def react(user:, discussion_id:, content:)
      discussion = reactable_discussion_for(user: user, discussion_id: discussion_id)

      if discussion.present?
        existing_reaction = user.discussion_reactions.find_by(
          discussion: discussion,
          content: content,
        )

        if existing_reaction.present?
          RecordStatus.new([existing_reaction, :exists])
        else
          new_discussion_reaction = create(
            user: user,
            discussion: discussion,
            content: content,
          ).tap do |_discussion_reaction|
            discussion.notify_socket_subscribers
            discussion.synchronize_search_index

            GitHub.dogstats.increment(
              "discussion_reaction",
              tags: ["action:create", "type:#{content}"],
            )
          end

          RecordStatus.new([new_discussion_reaction, :created])
        end
      else
        RecordStatus.new([new, :invalid])
      end
    end

    # Public: Idempotent all-purpose interface for ensuring a reaction DOES NOT
    # exist between users and discussions.
    # Performs permissions checks.
    #
    # user          - User: The user having this reaction
    # discussion_id - Integer: The ID of the discussion of this reaction
    # content       - String: One of the members of valid_content
    #
    # Returns: A DiscussionReaction in the appropriate state for the discussion
    # and user.
    sig { params(user: T.untyped, discussion_id: T.untyped, content: T.untyped).returns(T.untyped) }
    def unreact(user:, discussion_id:, content:)
      discussion = reactable_discussion_for(user: user, discussion_id: discussion_id)

      if discussion.present?
        existing_reaction = user.discussion_reactions.find_by(
          discussion: discussion,
          content: content,
        )

        if existing_reaction.present?
          transaction do
            existing_reaction.destroy
            discussion.notify_socket_subscribers
            discussion.synchronize_search_index

            GitHub.dogstats.increment(
              "discussion_reaction",
              tags: ["action:destroy", "type:#{content}"],
            )
            RecordStatus.new([existing_reaction, :deleted])
          end
        else
          unpersisted_discussion_reaction = new(
            user: user,
            discussion: discussion,
            content: content,
          )
          RecordStatus.new([unpersisted_discussion_reaction, :deleted])
        end
      else
        RecordStatus.new([new, :invalid])
      end
    end

    # Public: determine whether a given discussion is "unlocked" for a user
    sig { params(user: T.untyped, discussion: T.untyped).returns(T.untyped) }
    def discussion_unlocked?(user, discussion)
      async_discussion_unlocked?(user, discussion).sync
    end
    alias_method :subject_unlocked?, :discussion_unlocked?

    sig { params(user: T.untyped, discussion: T.untyped).returns(T.untyped) }
    def async_discussion_unlocked?(user, discussion)
      return Promise.resolve(false) unless user

      discussion.async_locked_for?(user).then { |locked| !locked }
    end

    # Public: Can this viewer add or remove a reaction on this Discussion?
    #
    # viewer - a User, Bot, or `nil`.
    # discussion - a Discussion instance that's the prospective reaction subject.
    # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
    #   check will be performed asynchronously during this call; if `true` or `false` are specified, the interaction
    #   check will be skipped and the provided value will be used instead.
    #
    # Returns a Promise that resolves to `true` or `false`.
    sig { params(viewer: T.untyped, discussion: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
    def async_viewer_can_react?(viewer, discussion, interaction_allowed: nil)
      return Promise.resolve(false) unless discussion && viewer

      async_actor_can_react_to?(viewer, discussion, interaction_allowed: interaction_allowed)
    end

    # For compatibility with Reaction.
    sig { params(actor: T.untyped, discussion: T.untyped, repository: T.untyped).returns(T.untyped) }
    def actor_can_react_to?(actor, discussion, repository: nil)
      async_actor_can_react_to?(actor, discussion).sync
    end

    # Public: Fetches data about reactions for a group of discussions.
    #
    # discussion_ids - an array of discussion IDs
    #
    # Returns a hash with discussion ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that discussion.
    sig { params(discussion_ids: T.untyped).returns(T.untyped) }
    def reaction_count_by_content_by_discussion_id(discussion_ids:)
      where(discussion_id: discussion_ids).
        group(:discussion_id, :content).
        count.
        each_with_object(Hash.new { |h, k| h[k] = {} }) do |((discussion_id, content), reaction_count), result|
          result[discussion_id][content] = reaction_count
        end
    end

    # Public: Fetches data about reactions by a viewer to a group of discussions.
    #
    # viewer - a User
    # discussion_ids - an array of discussion IDs
    #
    # Returns a hash with discussion ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that discussion.
    sig { params(viewer: T.untyped, discussion_ids: T.untyped).returns(T.untyped) }
    def viewer_reaction_contents_by_discussion_id(viewer:, discussion_ids:)
      where(discussion_id: discussion_ids, user: viewer).
        pluck(:discussion_id, :content).
        each_with_object(Hash.new { |h, k| h[k] = [] }) do |(discussion_id, content), result|
          result[discussion_id] << content
        end
    end

    private

    # Internal: Does the discussion exist and does the user have permission to
    # react to it?
    # Returns: The Discussion instance
    sig { params(user: T.untyped, discussion_id: T.untyped).returns(T.untyped) }
    def reactable_discussion_for(user:, discussion_id:)
      return unless user && discussion_id

      discussion = Discussion.find_by(id: discussion_id)

      if async_viewer_can_react?(user, discussion).sync
        discussion
      end
    end

    # Internal: Common actor reaction permission check logic.
    #
    # actor - a User or Bot.
    # discussion - a Discussion instance that's the prospective reaction subject.
    # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
    #   check will be performed asynchronously during this call; if `true` or `false` are specified, the interaction
    #   check will be skipped and the provided value will be used instead.
    #
    # Returns a Promise that resolves to `true` or `false`.
    sig { params(actor: T.untyped, discussion: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
    def async_actor_can_react_to?(actor, discussion, interaction_allowed: nil)
      interaction_promise = if interaction_allowed.nil? && !actor.can_have_granular_permissions?
        discussion.async_repository.then do |repo|
          User::InteractionAbility.async_interaction_allowed?(user: actor, repository: repo)
        end
      else
        Promise.resolve(interaction_allowed)
      end

      interaction_promise.then do |interaction_allowed|
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :toggle_discussion_reaction,
          actor: actor,
          subject: discussion,
          context: {
            "subject.repository.interaction_allowed" => interaction_allowed,
          },
        ).then(&:allow?)
      end
    end
  end

  sig { returns Emotion }
  def emotion
    Emotion.find(content)
  end

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_reaction.create", reaction: self
    GitHub.instrument "discussion_reaction.created", reaction: self

    message = {
      repository_id: discussion&.repository&.id,
      repository: discussion&.repository,
      repository_owner: discussion&.repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: user&.id,
      actor: user,
      action: :ACTION_REACTION_ADDED,
      action_timestamp: created_at,
      reaction: "REACTION_#{emotion.platform_enum}".to_sym,
    }
    GlobalInstrumenter.instrument "discussions_reaction", message
  end

  sig { void }
  def instrument_deletion_event
    GlobalInstrumenter.instrument "discussion_reaction.delete", reaction: self
    GitHub.instrument "discussion_reaction.deleted", reaction: self

    message = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: user&.id,
      actor: user,
      action: :ACTION_REACTION_REMOVED,
      action_timestamp: Time.now,
      reaction: "REACTION_#{emotion.platform_enum}".to_sym,
    }
    GlobalInstrumenter.instrument "discussions_reaction", message
  end

  sig { returns String }
  def platform_type_name
    "Reaction"
  end

  class RecordStatus < SimpleDelegator
    extend T::Helpers

    attr_reader :status

    VALID_STATUSES = [:created, :exists, :invalid, :deleted]

    sig { params(reaction_status: T.untyped).void }
    def initialize(reaction_status)
      reaction, @status = *reaction_status
      Kernel.raise ArgumentError.new("Invalid status: #{@status}") unless VALID_STATUSES.include?(@status)
      super(reaction)
    end

    sig { returns T::Boolean }
    def created?
      status == :created
    end

    sig { returns T::Boolean }
    def exists?
      status == :exists
    end
  end

  private

  sig { void }
  def count_daily_contributors
    return unless repository.present?
    created_at = self.created_at || Time.current
    CommunityInsights::DiscussionsDailyContributorsJob.perform_later(repository.id, created_at.to_date)
  end
end
