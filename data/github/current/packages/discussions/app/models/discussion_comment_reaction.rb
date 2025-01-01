# typed: true
# frozen_string_literal: true

class DiscussionCommentReaction < ApplicationRecord::Domain::Discussions
  include GitHub::Relay::GlobalIdentification
  include Spam::Spammable
  include InteractionBanValidation

  belongs_to :user, required: true
  belongs_to :discussion_comment, required: true

  sig { returns Promise[T.nilable(DiscussionComment)] }
  def async_subject
    async_discussion_comment
  end

  has_one :discussion, through: :discussion_comment

  setup_spammable(:user)

  validates :content, inclusion: { in: Emotion.all.map(&:content) }
  validate :user_can_interact, on: :create

  delegate :repository, to: :discussion_comment, allow_nil: true

  # Hydro instrumentation
  after_commit :instrument_creation_event, on: :create
  after_destroy_commit :instrument_deletion_event

  # Community Insights data
  after_commit :count_daily_contributors, on: [:create, :destroy]

  scope :for_discussion, ->(discussion_id) do
    joins(:discussion_comment).merge(DiscussionComment.for_discussion(discussion_id))
  end

  class << self
    # Public: Idempotent all-purpose interface for ensuring a discussion
    # comment reaction exists between users and discussion comments.
    # Performs permissions checks and prevents duplicates.
    #
    # user                  - User: The user having this reaction
    # discussion_comment_id - Integer: The ID of the discussion comment of this
    # reaction
    # content               - String: One of the members of Emotion.all.map(&:content)
    #
    # Returns: A DiscussionCommentReaction in the appropriate state for the
    # discussion comment and user.
    sig { params(user: T.untyped, discussion_comment_id: T.untyped, content: T.untyped).returns(T.untyped) }
    def react(user:, discussion_comment_id:, content:)
      discussion_comment = reactable_discussion_comment_for(
        user: user,
        discussion_comment_id: discussion_comment_id,
      )

      if discussion_comment.present?
        existing_reaction = user.discussion_comment_reactions.find_by(
          discussion_comment: discussion_comment,
          content: content,
        )

        if existing_reaction.present?
          DiscussionCommentReaction::RecordStatus.new([existing_reaction, :exists])
        else
          new_discussion_comment_reaction = create(
            user: user,
            discussion_comment: discussion_comment,
            content: content,
          ).tap do |_discussion_comment_reaction|
            discussion_comment.notify_socket_subscribers
            discussion_comment.synchronize_search_index

            GitHub.dogstats.increment(
              "discussion_comment_reaction",
              tags: ["action:create", "type:#{content}"],
            )
          end

          DiscussionCommentReaction::RecordStatus.new([new_discussion_comment_reaction, :created])
        end
      else
        Reaction::RecordStatus.new([new, :invalid])
      end
    end

    # Public: Idempotent all-purpose interface for ensuring a reaction DOES NOT
    # exist between users and discussion comments.
    # Performs permissions checks.
    #
    # user                  - User: The user having this reaction
    # discussion_comment_id - Integer: The ID of the discussion comment of this
    # reaction
    # content               - String: One of the members of valid_content
    #
    # Returns: A DiscussionCommentReaction in the appropriate state for the
    # discussion comment and user.
    sig { params(user: T.untyped, discussion_comment_id: T.untyped, content: T.untyped).returns(T.untyped) }
    def unreact(user:, discussion_comment_id:, content:)
      discussion_comment = reactable_discussion_comment_for(
        user: user,
        discussion_comment_id: discussion_comment_id,
      )

      if discussion_comment.present?
        existing_reaction = user.discussion_comment_reactions.find_by(
          discussion_comment: discussion_comment,
          content: content,
        )

        if existing_reaction.present?
          existing_reaction.destroy
          discussion_comment.notify_socket_subscribers
          discussion_comment.synchronize_search_index

          GitHub.dogstats.increment(
            "discussion_comment_reaction",
            tags: ["action:destroy", "type:#{content}"],
          )
          RecordStatus.new([existing_reaction, :deleted])
        else
          unpersisted_discussion_comment_reaction = new(
            user: user,
            discussion_comment: discussion_comment,
            content: content,
          )
          RecordStatus.new([unpersisted_discussion_comment_reaction, :deleted])
        end
      else
        RecordStatus.new([new, :invalid])
      end
    end

    # Public: determine whether a given discussion_comment is "unlocked" for a
    # user
    sig { params(user: T.untyped, discussion_comment: T.untyped).returns(T.untyped) }
    def discussion_comment_unlocked?(user, discussion_comment)
      async_discussion_comment_unlocked?(user, discussion_comment).sync
    end
    alias_method :subject_unlocked?, :discussion_comment_unlocked?

    sig { params(user: T.untyped, discussion_comment: T.untyped).returns(T.untyped) }
    def async_discussion_comment_unlocked?(user, discussion_comment)
      return Promise.resolve(false) unless user

      discussion_comment.async_locked_for?(user).then { |locked| !locked }
    end

    sig do
      params(
        viewer: T.untyped,
        discussion_comment: T.untyped,
        interaction_allowed: T.untyped
      ).returns(T.untyped)
    end
    def async_viewer_can_react?(viewer, discussion_comment, interaction_allowed: nil)
      return Promise.resolve(false) unless discussion_comment && viewer

      async_actor_can_react_to?(viewer, discussion_comment, interaction_allowed: interaction_allowed)
    end

    # For compatibility with Reaction.
    sig { params(actor: T.untyped, discussion_comment: T.untyped, repository: T.untyped).returns(T.untyped) }
    def actor_can_react_to?(actor, discussion_comment, repository: nil)
      async_actor_can_react_to?(actor, discussion_comment).sync
    end

    private

    # Internal: Does the discussion_comment exist and does the user have
    # permission to react to it?
    #
    # Returns: The DiscussionComment instance
    sig { params(user: T.untyped, discussion_comment_id: T.untyped).returns(T.untyped) }
    def reactable_discussion_comment_for(user:, discussion_comment_id:)
      return unless user && discussion_comment_id

      discussion_comment = DiscussionComment.find_by(id: discussion_comment_id)

      if async_viewer_can_react?(user, discussion_comment).sync
        discussion_comment
      end
    end

    sig { params(actor: T.untyped, discussion_comment: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
    def async_actor_can_react_to?(actor, discussion_comment, interaction_allowed: nil)
      interaction_promise = if interaction_allowed.nil? && !actor.can_have_granular_permissions?
        discussion_comment.async_repository.then do |repo|
          User::InteractionAbility.async_interaction_allowed?(user: actor, repository: repo)
        end
      else
        Promise.resolve(interaction_allowed)
      end

      interaction_promise.then do |interaction_allowed|
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :toggle_discussion_comment_reaction,
          actor: actor,
          subject: discussion_comment,
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
    GlobalInstrumenter.instrument "discussion_comment_reaction.create", reaction: self
    GitHub.instrument "discussion_comment_reaction.created", reaction: self

    message = {
      repository_id: discussion_comment&.repository_id,
      repository: discussion_comment&.repository,
      repository_owner: discussion&.repository&.owner,
      discussion_id: discussion_comment&.discussion_id,
      discussion: discussion_comment&.discussion,
      discussion_comment_id: discussion_comment&.id,
      discussion_comment: discussion_comment,
      actor_id: user&.id,
      actor: user,
      action: :ACTION_REACTION_ADDED,
      action_timestamp: created_at,
      reaction: "REACTION_#{emotion.platform_enum}".to_sym,
    }
    GlobalInstrumenter.instrument "discussions_comment_reaction", message
  end

  sig { void }
  def instrument_deletion_event
    GlobalInstrumenter.instrument "discussion_comment_reaction.delete", reaction: self
    GitHub.instrument "discussion_comment_reaction.deleted", reaction: self

    message = {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      discussion_comment_id: discussion_comment&.id,
      discussion_comment: discussion_comment,
      actor_id: user&.id,
      actor: user,
      action: :ACTION_REACTION_DELETED,
      action_timestamp: Time.now,
      reaction: "REACTION_#{emotion.platform_enum}".to_sym,
    }
    GlobalInstrumenter.instrument "discussions_comment_reaction", message
  end

  sig { returns(String) }
  def platform_type_name
    "Reaction"
  end

  class RecordStatus < SimpleDelegator
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
