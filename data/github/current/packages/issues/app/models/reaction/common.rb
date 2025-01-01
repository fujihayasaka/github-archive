# typed: true
# frozen_string_literal: true

# Public: A mixin to reduce code duplication among
# the `*Reaction` ActiveRecord models that live under
# ApplicationRecord::Domain::IssuesPullRequests.
module Reaction::Common
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationRecord::Domain::IssuesPullRequests }

  VALID_EMOTIONS = Emotion.all.map(&:content).to_set.freeze

  class_methods do
    # Public: Idempotent all-purpose interface for ensuring a reaction exists
    # between users and subjects.
    # Performs permissions checks and prevents duplicates.
    #
    # user          - User: The user having this reaction
    # subject_id    - Integer: The ID of the subject of this reaction
    # content       - String: One of the members of valid_content
    #
    # Returns: A Reaction in the appropriate state for the subject and user.
    def react(user:, subject_id:, content:)
      if subject = reactable_subject_for(user: user, subject_id: subject_id)
        reaction = T.unsafe(self).find_or_create_by(attributes_for(user: user, content: content, subject: subject))
        reaction_status = reaction.previously_new_record? ? :created : :exists

        # Because create is used in find_or_create_by instead of create! there will be no validation
        # exceptions thrown on save. Callers do not expect an exception either, so we will manually
        # check the reaction for validity and use the :invalid record status to indicate that the
        # reaction is invalid, has errors, and was not saved to the DB
        return record_status([reaction, :invalid]) unless reaction.valid?

        if reaction_status == :created
          subject.notify_socket_subscribers
          subject.notify_graphql_subscribers if subject.respond_to?(:notify_graphql_subscribers)
          subject.synchronize_search_index if subject.respond_to?(:synchronize_search_index)
          GitHub.dogstats.increment("reaction", tags: ["action:create", "type:#{content}"])
        end

        record_status([reaction, reaction_status])
      else
        # User can't react to this subject. Return a generic "invalid" reaction
        record_status([T.unsafe(self).new, :invalid])
      end
    end

    # Public: Idempotent all-purpose interface for ensuring a reaction DOES NOT
    # exist between users and subjects.
    # Performs permissions checks.
    #
    # user          - User: The user having this reaction
    # subject_id    - Integer: The ID of the subject of this reaction
    # content       - String: One of the members of valid_content
    #
    # Returns: A Reaction in the appropriate state for the subject and user.
    def unreact(user:, subject_id:, content:)
      if subject = reactable_subject_for(user: user, subject_id: subject_id)
        if existing_reaction = existing_reaction_for(user: user, content: content, subject: subject)
          # Reaction exists. Destroy it and return the object.
          existing_reaction.destroy
          subject.notify_socket_subscribers
          subject.notify_graphql_subscribers if subject.respond_to?(:notify_graphql_subscribers)

          if subject.respond_to?(:synchronize_search_index)
            subject.synchronize_search_index
          end

          GitHub.dogstats.increment("reaction", tags: ["action:destroy", "type:#{content}"])

          record_status([existing_reaction, :deleted])
        else
          # Destroying a reaction that doesn't exist.
          # We simply return a seemingly valid, but unpersisted reaction
          unpersisted_reaction = T.unsafe(self).new(attributes_for(user: user, subject: subject, content: content))
          record_status([unpersisted_reaction, :deleted])
        end
      else
        # User can't react to this subject. Return a generic "invalid" reaction
        record_status([T.unsafe(self).new, :invalid])
      end
    end

    # Public: determine whether a given subject is "unlocked" for a user
    def subject_unlocked?(user, subject)
      async_subject_unlocked?(user, subject).sync
    end

    def async_subject_unlocked?(user, subject)
      return Promise.resolve(false) unless user

      case subject
      when Issue
        subject.async_locked?.then { |locked| !locked }
      when IssueComment, PullRequest
        subject.async_issue.then(&:async_locked?).then { |locked| !locked }
      when PullRequestReview, PullRequestReviewComment
        subject.async_pull_request.then(&:async_issue).then(&:async_locked?).then { |locked| !locked }
      when CommitComment
        Platform::Loaders::CommitCommentsLocked.load(subject.repository_id, subject.commit_id).then do |locked|
          !locked
        end
      else
        Promise.resolve(false)
      end
    end

    def async_viewer_can_react?(viewer, subject)
      return Promise.resolve(false) unless subject && viewer

      if subject.respond_to?(:async_repository)
        subject.async_repository.then do |repository|
          async_actor_can_react_to?(viewer, subject, repository: repository)
        end
      else
        async_actor_can_react_to?(viewer, subject)
      end
    end

    # Can an actor react to this subject and repository?
    def actor_can_react_to?(actor, subject, repository: nil)
      async_actor_can_react_to?(actor, subject, repository: repository).sync
    end

    def async_actor_can_react_to?(actor, subject, repository: nil)
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

    def record_status(reaction_status)
      @record_status_class ||= Class.new(SimpleDelegator) do
        attr_reader :status

        def initialize(reaction_status)
          reaction, @status = *reaction_status
          unless [:created, :exists, :invalid, :deleted].include?(@status)
            Kernel.raise ArgumentError.new("Invalid status: #{@status}")
          end
          super(reaction)
        end

        def created?
          T.unsafe(self).status == :created
        end

        def exists?
          T.unsafe(self).status == :exists
        end
      end

      @record_status_class.new(reaction_status)
    end

    def graphql_name
      "Platform::Objects::Reaction"
    end

    def subject_association
      subject_name.underscore
    end

    def subject_association_column_name
      "#{subject_name.underscore}_id"
    end

    def subject_name
      T.unsafe(self).to_s.sub(/Reaction\z/, "")
    end

    private

    def attributes_for(user:, content:, subject:)
      { content: content, user_id: user.id }.tap do |attrs|
        attrs["#{subject_association}_id"] = subject.id
        attrs["repository_id"] = subject.repository_id
      end
    end

    def existing_reaction_for(user:, content:, subject:)
      T.unsafe(self).where(attributes_for(user: user, content: content, subject: subject)).first
    end

    def subject_class
      subject_name.safe_constantize
    end

    def find_subject_by_id(subject_id)
      subject_class.find_by_id(subject_id)
    end

    # Internal: COULD a IntegrationInstallation react
    # to this subject and repository?
    #
    # An IntegrationInstallation cannot react on it's own
    # because it's not a User. However we need to see if it
    # could for when a User reacts via an Integration.
    def async_installation_could_react_to?(actor, subject, repository: nil)
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
      end
    end

    def installation_could_react_to?(actor, subject, repository: nil)
      async_installation_could_react_to?(actor, subject, repository: repository).sync
    end

    # Internal: Does the subject exist and does the user have permission to react
    # to it?
    # Returns: The Subject instance
    def reactable_subject_for(user:, subject_id:)
      return unless user

      if (subject = find_subject_by_id(subject_id))
        if self.async_viewer_can_react?(user, subject).sync
          subject
        end
      end
    end

    def async_user_can_react_to?(user, subject)
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

    # Internal: Can a user react to this subject and repository?
    def user_can_react_to?(user, subject)
      async_user_can_react_to?(user, subject).sync
    end
  end

  included do
    T.bind(self, T.class_of(ApplicationRecord::Domain::IssuesPullRequests))

    include GitHub::Relay::GlobalIdentification
    include Spam::Spammable
    include InteractionBanValidation
    #include Reactable

    belongs_to :repository
    belongs_to :user

    belongs_to T.unsafe(self).subject_association.to_sym, required: true

    validates_presence_of :repository_id
    validates_presence_of :user_id

    validates :content, inclusion: { in: VALID_EMOTIONS }

    # Defined in: InteractionBanValidation.
    validate :user_can_interact, on: :create

    # Hydro instrumentation
    after_create_commit :instrument_creation_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks

    # Defined in Spam::Spammable.
    T.unsafe(self).setup_spammable(:user)
  end

  def emotion
    Emotion.find(T.unsafe(self).content)
  end

  def platform_type_name
    "#{self.class}"
  end

  def subject
    public_send(T.unsafe(self.class).subject_association)
  end

  def async_subject
    public_send("async_#{T.unsafe(self.class).subject_association}")
  end

  def subject_id
    public_send("#{T.unsafe(self.class).subject_association}_id")
  end

  def subject_type
    T.unsafe(self.class).subject_name
  end

  def repository
    subject.try(:repository)
  end

  def instrument_creation_event
    GlobalInstrumenter.instrument "reaction.created", reaction: self
  end
end
