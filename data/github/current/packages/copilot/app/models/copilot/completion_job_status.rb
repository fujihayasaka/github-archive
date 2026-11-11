# typed: strict
# frozen_string_literal: true

module Copilot
  class CompletionJobStatus < Copilot::JobStatus

    ID_PREFIX = T.let("copilot-completion", String)
    DEFAULT_OVERALL_TTL = T.let(3.days, ActiveSupport::Duration)
    COMPLETED_JOB_TTL = T.let(1.day, ActiveSupport::Duration)

    sig { returns(T.any(::User, Symbol)) }
    def target_for_conditional_access
      repository&.target_for_conditional_access || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    sig do
      override
        .params(attributes: T::Hash[Symbol, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped
        .returns(Copilot::CompletionJobStatus)
    end
    def self.create(attributes = {})
      super(
        attributes.merge(
          id: generate_id,
          ttl: DEFAULT_OVERALL_TTL
        )
      )
    end
    private_class_method :new # Force use of create

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      id.start_with?(ID_PREFIX)
    end

    sig { override.params(attributes: T::Hash[T.untyped, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
    def initialize(attributes = {})
      super

      @repo_memo = T.let({}, T::Hash[Integer, T.nilable(Repository)])
      @actor_memo = T.let({}, T::Hash[Integer, T.nilable(::User)])

      self.repository = attributes[:repository] if attributes.key?(:repository)
      self.actor = attributes[:actor] if attributes.key?(:actor)
    end

    sig { override.params(ttl: ActiveSupport::Duration).void }
    def success!(ttl: COMPLETED_JOB_TTL)
      super
    end

    sig { override.params(message: T.nilable(String), ttl: ActiveSupport::Duration).void }
    def error!(message = nil, ttl: COMPLETED_JOB_TTL)
      super
    end

    sig { returns(T.nilable(Repository)) }
    def repository
      return unless repo_id = context&.fetch(:repository_id)

      @repo_memo[repo_id] ||= ::Repositories::Public.find_active(repo_id)
    end

    sig { params(repo: T.nilable(Repository)).returns(T.nilable(Repository)) }
    def repository=(repo)
      repo_id = repo&.id

      self.context ||= {}
      T.must(self.context)[:repository_id] = repo_id
      @repo_memo[repo_id] = repo if repo_id
    end

    sig { returns(T.nilable(::User)) }
    def actor
      return unless actor_id = context&.fetch(:actor_id)

      @actor_memo[actor_id] ||= ::User.find(actor_id)
    end

    sig { params(actor: T.nilable(::User)).returns(T.nilable(::User)) }
    def actor=(actor)
      actor_id = actor&.id

      self.context ||= {}
      T.must(self.context)[:actor_id] = actor_id
      @actor_memo[actor_id] = actor if actor_id
    end


    # Returns attributes that are used to initialize new instances of this class.
    sig { returns(String) }
    private_class_method def self.generate_id
      [ID_PREFIX, SecureRandom.uuid].join(":")
    end
  end
end
