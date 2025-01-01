# typed: strict
# frozen_string_literal: true

class Restorable
  # Private: Augment the public IVisibilityChangedRepository interface with package-private methods that are shared
  # between the null object and its real implementation, but perform write operations on the model. To expose this
  # functionality outside of the package, add dedicated methods to the public domain interface that load the correct
  # restorable and call these methods.
  module IPrivateVisibilityChangedRepository
    extend T::Helpers
    include Restorables::IVisibilityChangedRepository

    abstract!

    sig { abstract.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars); end

    sig { abstract.void }
    def save_stars_complete; end

    sig { abstract.void }
    def restore; end

    sig { abstract.void }
    def cancel; end
  end
end
