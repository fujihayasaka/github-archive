# typed: true
# frozen_string_literal: true

# Emoji-ish reactions that can be attached to issues, pull requests, releases and
# comments.
class Reaction < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification
  include Spam::Spammable
  include InteractionBanValidation
  include Reactable

  belongs_to :user
  belongs_to :subject, polymorphic: true

  setup_spammable(:user)

  validates_presence_of :user_id
  validate :subject_and_content_are_valid

  # We use a lambda here so that we can stub the valid types in our tests.
  validates_inclusion_of :subject_type, in: lambda { |_| valid_subject_types }

  validate :user_can_interact, on: :create

  # Hydro instrumentation
  after_commit :instrument_creation_event, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  VALID_SUBJECT_TYPES = %w(
      CommitComment
      Discussion
      DiscussionComment
      DiscussionPost
      DiscussionPostReply
      FeedPost
      FeedPostComment
      Issue
      IssueComment
      PullRequestReview
      PullRequestReviewComment
      Release
      RepositoryAdvisory
      RepositoryAdvisoryComment
  ).to_set.freeze

  def repository
    subject.try(:repository)
  end

  # Validation: Ensure the subject exists and defines the array of emotions it accepts
  # Check that content is included in the list of valid emotions
  # The subject will contain a definition for emotions if it includes the reactable module
  def subject_and_content_are_valid
    valid_emotions = []

    if subject.nil?
      errors.add :subject, "is not a suitable subject for this reaction"
    elsif !subject.class.respond_to?(:emotions)
      errors.add :subject, "is not a suitable subject for this reaction"
    else
      valid_emotions = subject.class.emotions.map(&:content)
    end

    return if valid_emotions.include? content

    errors.add :content, "is not a valid emotion for this subject"
  end

  # Valid types (classes in this list should include Reaction::Subject)
  def self.valid_subject_types
    VALID_SUBJECT_TYPES
  end

  # Public: Can the specified object be the subject of a reaction?
  #
  # object - Object to check subject validity for.
  #
  # Returns a boolean.
  def self.valid_subject?(object)
    object.respond_to?(:reactable?) && object.reactable?
  end

  # Public: Idempotent all-purpose interface for ensuring a reaction exists
  # between users and subjects.
  # Performs permissions checks and prevents duplicates.
  #
  # user          - User: The user having this reaction
  # subject_id    - Integer: The ID of the subject of this reaction
  # subject_type  - String: The class name of the subject
  # content       - String: One of the members of valid_content
  #
  # Returns: A Reaction in the appropriate state for the subject and user.
  def self.react(user:, subject_id:, subject_type:, content:)
    if subject = reactable_subject_for(user: user, subject_id: subject_id, subject_type: subject_type)
      if SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
        klass = "#{subject.class.name}Reaction".constantize
        return klass.react(user: user, subject_id: subject.id, content: content)
      end

      if existing_reaction = subject.reactions.where(user: user, content: content).first
        # Reaction exists. Return it.
        Reaction::RecordStatus.new([existing_reaction, :exists])
      else
        # Reaction does not already exist. Create one.
        new_reaction = create(user: user, subject: subject, content: content).tap do |reaction|
          # Because create is used above instead of create! there will be no validation exceptions thrown on save.
          # Callers do not expect an exception either, so we will manually check the reaction for validity and
          # use the :invalid record status to indicate that the reaction is invalid, has errors, and was not saved to the DB
          return Reaction::RecordStatus.new([reaction, :invalid]) unless reaction.valid?

          subject.notify_socket_subscribers

          if subject.respond_to?(:synchronize_search_index)
            subject.synchronize_search_index
          end

          GitHub.dogstats.increment("reaction", tags: ["action:create", "type:#{content}"])
        end
        Reaction::RecordStatus.new([new_reaction, :created])
      end
    else
      # User can't react to this subject. Return a generic "invalid" reaction
      Reaction::RecordStatus.new([new, :invalid])
    end
  end

  # Public: Idempotent all-purpose interface for ensuring a reaction DOES NOT
  # exist between users and subjects.
  # Performs permissions checks.
  #
  # user          - User: The user having this reaction
  # subject_id    - Integer: The ID of the subject of this reaction
  # subject_type  - String: The class name of the subject
  # content       - String: One of the members of valid_content
  #
  # Returns: A Reaction in the appropriate state for the subject and user.
  def self.unreact(user:, subject_id:, subject_type:, content:)
    if subject = reactable_subject_for(user: user, subject_id: subject_id, subject_type: subject_type)
      if SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
        klass = "#{subject.class.name}Reaction".constantize
        return klass.unreact(user: user, subject_id: subject.id, content: content)
      end

      if existing_reaction = user.reactions.where(subject_id: subject.id, subject_type: subject.class, content: content).first
        GitHub.instrument "reaction.deleted", reaction: existing_reaction

        # Reaction exists. Destroy it and return the object.
        existing_reaction.destroy
        subject.notify_socket_subscribers

        if subject.respond_to?(:synchronize_search_index)
          subject.synchronize_search_index
        end

        GitHub.dogstats.increment("reaction", tags: ["action:destroy", "type:#{content}"])
        Reaction::RecordStatus.new([existing_reaction, :deleted])
      else
        # Destroying a reaction that doesn't exist.
        # We simply return a seemingly valid, but unpersisted reaction
        unpersisted_reaction = new(user: user, subject: subject, content: content)
        Reaction::RecordStatus.new([unpersisted_reaction, :deleted])
      end
    else
      # User can't react to this subject. Return a generic "invalid" reaction
      Reaction::RecordStatus.new([new, :invalid])
    end
  end

  # Public: determine whether a given subject is "unlocked" for a user
  def self.subject_unlocked?(user, subject)
    async_subject_unlocked?(user, subject).sync
  end

  def self.async_subject_unlocked?(user, subject)
    return Promise.resolve(false) unless user

    case subject
    when DiscussionPost, DiscussionPostReply
      Promise.resolve(true)
    when RepositoryAdvisory, RepositoryAdvisoryComment
      Promise.resolve(true)
    when Issue
      subject.async_locked?.then { |locked| !locked }
    when IssueComment, PullRequest
      subject.async_issue.then { |x| T.must(x).async_locked? }.then { |locked| !locked }
    when PullRequestReview, PullRequestReviewComment
      subject.async_pull_request.then { |x| T.must(x).async_issue }.then(&:async_locked?).then { |locked| !locked }
    when CommitComment
      Platform::Loaders::CommitCommentsLocked.load(subject.repository_id, subject.commit_id).then do |locked|
        !locked
      end
    when Discussion, DiscussionComment
      subject.async_locked_for?(user).then { |locked| !locked }
    when Release
      Promise.resolve(true)
    when FeedPost, FeedPostComment
      Promise.resolve(true)
    else
      Promise.resolve(false)
    end
  end

  def emotion
    Emotion.find(content)
  end

  def self.async_viewer_can_react?(viewer, subject)
    return Promise.resolve(false) unless subject && viewer

    if subject.respond_to?(:async_repository)
      subject.async_repository.then do |repository|
        async_actor_can_react_to?(viewer, subject, repository: repository)
      end
    else
      async_actor_can_react_to?(viewer, subject)
    end
  end

  # Internal: Does the subject exist and does the user have permission to react
  # to it?
  # Returns: The Subject instance
  def self.reactable_subject_for(user:, subject_id:, subject_type:)
    return unless user

    if (subject = find_subject(subject_id, subject_type))
      if self.async_viewer_can_react?(user, subject).sync
        subject
      end
    end
  end
  private_class_method :reactable_subject_for

  # Internal: Finds a Reaction subject
  def self.find_subject(subject_id, subject_type)
    return unless subject_id && subject_type
    subject_type = subject_type.underscore.classify
    return unless valid_subject_type?(subject_type)

    subject_type.safe_constantize.find_by_id(subject_id)
  end

  # Internal: Is the subject_type a valid class for a reaction subject?
  def self.valid_subject_type?(subject_type)
    subject_type && valid_subject_types.include?(subject_type)
  end
  private_class_method :valid_subject_type?

  def self.async_user_can_react_to?(user, subject)
    return Promise.resolve(false) if user.must_verify_email?
    return Promise.resolve(false) unless subject

    subject.async_user.then do |subject_user|
      subject.async_reaction_admin.then do |admin|
        Promise.all([subject.async_readable_by?(user),
                     async_subject_unlocked?(user, subject),
                     user.async_blocked_by?(subject_user),
                     user.async_blocked_by?(admin),
        ]).then do |readable, unlocked, blocked_by_user, blocked_by_admin|
          readable && unlocked && !blocked_by_user && !blocked_by_admin
        end
      end
    end
  end
  private_class_method :async_user_can_react_to?

  # Internal: Can a user react to this subject and repository?
  def self.user_can_react_to?(user, subject)
    async_user_can_react_to?(user, subject).sync
  end
  private_class_method :user_can_react_to?

  # Internal: Can an actor react to this subject and repository?
  def self.actor_can_react_to?(actor, subject, repository: nil)
    async_actor_can_react_to?(actor, subject, repository: repository).sync
  end

  def self.async_actor_can_react_to?(actor, subject, repository: nil)
    return Promise.resolve(false) unless actor

    if actor.can_have_granular_permissions?
      async_installation_could_react_to?(actor, subject, repository: repository)
    else
      User::InteractionAbility.async_interaction_allowed?(
        user: actor,
        repository: repository,
      ).then do |interaction_allowed|
        next false unless interaction_allowed

        async_user_can_react_to?(actor, subject)
      end
    end
  end

  # Internal: COULD a IntegrationInstallation react
  # to this subject and repository?
  #
  # An IntegrationInstallation cannot react on it's own
  # because it's not a User. However we need to see if it
  # could for when a User reacts via an Integration.
  def self.async_installation_could_react_to?(actor, subject, repository: nil)
    case subject
    when CommitComment
      repository.resources.contents.async_writable_by?(actor)
    when PullRequest
      repository.resources.pull_requests.async_writable_by?(actor)
    when Issue
      subject.async_pull_request.then do |pr|
        if pr
          repository.resources.pull_requests.async_writable_by?(actor)
        else
          repository.resources.issues.async_writable_by?(actor)
        end
      end
    when IssueComment
      subject.async_issue.then do |subject_parent|
        T.must(subject_parent).async_pull_request.then do |pr|
          if pr
            repository.resources.pull_requests.writable_by?(actor)
          else
            repository.resources.issues.writable_by?(actor)
          end
        end
      end
    when PullRequestReview, PullRequestReviewComment
      repository.resources.pull_requests.async_writable_by?(actor)
    when DiscussionPost, DiscussionPostReply
      subject.async_viewer_can_update?(actor)
    when Release
      subject.async_readable_by?(actor)
    end
  end
  private_class_method :async_installation_could_react_to?

  def self.installation_could_react_to?(actor, subject, repository: nil)
    async_installation_could_react_to?(actor, subject, repository: repository).sync
  end
  private_class_method :installation_could_react_to?

  def instrument_creation_event
    GlobalInstrumenter.instrument "reaction.created", reaction: self
    GitHub.instrument "reaction.created", reaction: self
  end
end
