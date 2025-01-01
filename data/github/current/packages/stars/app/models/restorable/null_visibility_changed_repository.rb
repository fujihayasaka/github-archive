# typed: strict
# frozen_string_literal: true

# Public: This is a null copy of Restorable::VisibilityChangedRepository returned when a restorable isn't found so
# that calling code doesn't have to use any conditionals and can just treat a restorable as a restorable.
#
# Generally, callers should use the state predicates #saving? or #restorable? to determine if the instance they have
# is appropriate for use.
class Restorable
  class NullVisibilityChangedRepository
    include Restorable::IVisibilityChangedRepository

    sig { params(repository: ::Repositories::IRepository).returns(IVisibilityChangedRepository) }
    def self.ensure_started(repository)
      new
    end

    sig { params(repository: ::Repositories::IRepository).returns(IVisibilityChangedRepository) }
    def self.continue(repository)
      new
    end

    sig { override.returns(T::Boolean) }
    def saving?
      false
    end

    sig { override.returns(T::Boolean) }
    def restorable?
      false
    end

    sig { override.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars) ; end

    # Public: Mark restorable_repository_stars as saved.
    sig { override.void }
    def save_stars_complete ; end
  end
end
