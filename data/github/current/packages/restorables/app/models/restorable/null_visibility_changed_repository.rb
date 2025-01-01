# typed: strict
# frozen_string_literal: true

# Public: This is a null copy of Restorable::VisibilityChangedRepository returned when a restorable isn't found so
# that calling code doesn't have to use any conditionals and can just treat a restorable as a restorable.
#
# Generally, callers should use the state predicates #saving? or #restorable? to determine if the instance they have
# is appropriate for use.
class Restorable
  class NullVisibilityChangedRepository
    include Restorable::IPrivateVisibilityChangedRepository

    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.ensure_started(repository)
      new
    end

    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
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

    sig { override.returns(T::Boolean) }
    def restoring?
      false
    end

    sig { override.returns(T::Boolean) }
    def restored?
      false
    end

    sig { override.returns(Time) }
    def updated_at
      Time.zone.now
    end

    sig { override.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars) ; end

    sig { override.void }
    def save_stars_complete ; end

    sig { override.void }
    def restore ; end

    sig { override.void }
    def cancel ; end
  end
end
