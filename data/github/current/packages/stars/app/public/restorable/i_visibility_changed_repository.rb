# typed: strict
# frozen_string_literal: true

class Restorable
  module IVisibilityChangedRepository
    extend T::Helpers

    abstract!

    sig { abstract.returns(T::Boolean) }
    def saving?; end

    sig { abstract.returns(T::Boolean) }
    def restorable?; end

    sig { abstract.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars); end

    sig { abstract.void }
    def save_stars_complete; end
  end
end
