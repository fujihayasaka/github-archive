# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueType
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    sig { abstract.params(selected: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    def memex_suggestion_hash(selected:); end

    sig { abstract.returns(T.nilable(String)) }
    def name; end

    sig do
      abstract.params(
        matrix: {
          disabled_allowed: T::Boolean
        }
      ).returns(T::Boolean)
    end
    def readable?(matrix); end
  end
end
