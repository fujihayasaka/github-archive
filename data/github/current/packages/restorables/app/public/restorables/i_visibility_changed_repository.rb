# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: Externally visible, read-only interface for repository visibility change restoration scenarios.
  module IVisibilityChangedRepository
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T::Boolean) }
    def saving?; end

    sig { abstract.returns(T::Boolean) }
    def restorable?; end

    sig { abstract.returns(T::Boolean) }
    def restoring?; end

    sig { abstract.returns(T::Boolean) }
    def restored?; end

    sig { abstract.returns(Time) }
    def updated_at; end
  end
end
