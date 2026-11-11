# typed: strict
# frozen_string_literal: true

class Restorable
  # Internal: A non-ActiveRecord class responsible for handling instrumentation events for visibility change
  # restoration operations. This implements the audit log events related to visibility change restoration actions
  # initiated from stafftools.
  #
  # Usage:
  #
  #   vcr = Restorable::VisibilityChangedRepository.find(123)
  #   restoration = Restorable::VisibilityChangeRestoration.new(vcr)
  #   restoration.start(actor: user)
  #   restoration.cancel(actor: user)
  #
  class VisibilityChangeRestoration
    include Instrumentation::Model
    include GitHub::Memoizer

    sig { params(visibility_changed_repository: Restorable::VisibilityChangedRepository).void }
    def initialize(visibility_changed_repository)
      @visibility_changed_repository_id = T.let(visibility_changed_repository.id, Integer)
      @restorable_id = T.let(visibility_changed_repository.restorable_id, Integer)
      @repository_id = T.let(visibility_changed_repository.repository_id, Integer)
    end

    # Public: Record the beginning of a visibility change restoration.
    #
    # actor - An optional User instance representing the actor initiating the restoration.
    #
    # Returns nothing.
    sig { params(actor: T.nilable(User)).void }
    def start(actor: nil)
      instrument(
        :start,
        actor: actor&.display_login,
        actor_id: actor&.id,
      )
    end

    # Public: Record the cancellation of a visibility change restoration.
    #
    # actor - An optional User instance representing the actor cancelling the restoration.
    #
    # Returns nothing.
    sig { params(actor: T.nilable(User)).void }
    def cancel(actor: nil)
      instrument(
        :cancel,
        actor: actor&.display_login,
        actor_id: actor&.id,
      )
    end

    # Public: Record the completion of a visibility change restoration.
    #
    # Returns nothing.
    sig { void }
    def complete
      instrument(:complete)
    end

    # Internal: Override the default event prefix so these actions appear in the audit log as
    # "visibility_change_restoration" instead of the more confusing "restorable_visibility_change_restoration".
    #
    # Returns a Symbol.
    sig { override.returns(Symbol) }
    def event_prefix
      :visibility_change_restoration
    end

    # Internal: The base event payload containing common attributes for all events.
    #
    # Returns a Hash.
    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        visibility_changed_repository_id: visibility_changed_repository_id,
        restorable_id: restorable_id,
        repo_id: repository_id,
        repo: repository&.name_with_display_owner,
      }
    end

    private

    sig { returns(Integer) }
    attr_reader :visibility_changed_repository_id

    sig { returns(Integer) }
    attr_reader :restorable_id

    sig { returns(Integer) }
    attr_reader :repository_id

    sig { returns(T.nilable(Repositories::IRepository)) }
    memoize def repository
      Repositories.domain.by_id(repository_id)
    end
  end
end
