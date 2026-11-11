# typed: strict
# frozen_string_literal: true

module Issues
  module IIssue
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def title; end

    sig { abstract.returns(T.nilable(String)) }
    def body; end

    sig { abstract.returns(T.nilable(String)) }
    def number; end

    sig { abstract.params(include_host: T::Boolean).returns(String) }
    def permalink(include_host: true); end

    sig { abstract.params(include_host: T::Boolean).returns(String) }
    def url(include_host: true); end

    # Returns either "open" or "closed" if the state of the issue is known, otherwise returns nil.
    sig { abstract.returns(T.nilable(String)) }
    def state; end

    # Returns "completed" (or, equivalently, `nil`), "closed", or "not_planned" as a descriptor for the
    # Issue's "closed" state. If the Issue's state is "open", this field has no meaning even if it contains data.
    sig { abstract.returns(T.nilable(String)) }
    def state_reason; end

    # Returns the times at which the Issue was closed, if any.
    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def closed_at; end

    # Returns the time at which the Issue was first persisted to the database.
    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def created_at; end

    # Returns id of the repository which the issue belongs to.
    sig { abstract.returns(Integer) }
    def repository_id; end

    sig { abstract.returns(T::Array[User]) }
    def assignees; end

    # Returns id of the user which the issue belongs to.
    sig { abstract.returns(Integer) }
    def user_id; end

    sig { abstract.returns(String) }
    def compressed_body; end

    sig { abstract.params(issue: IIssue, actor: User, time: Time).returns(T::Hash[Symbol, T.untyped]) }
    def record_reference_from(issue, actor, time); end
  end
end
