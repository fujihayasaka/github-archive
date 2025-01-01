# typed: strict
# frozen_string_literal: true

# ActionsCacheUsageCombined is a wrapper for ActionsCacheUsage active record and is created for artifact cache migration period.
# ActionsCacheUsage is populated by 2 systems: old - ArtifactCache and new - results.
# In order to make the trasition transparent for the users we need to combine the data from both systems.
# More details can be found in the issue https://github.com/github/actions-relaunch/issues/823
class ActionsCacheUsageCombined
  include GitHub::Memoizer

  sig { params(usages: T::Array[ActionsCacheUsage]).void }
  def initialize(usages)
    if usages.empty?
      return
    end
    if usages.map(&:repository_id).uniq.size != 1
      raise ArgumentError, "All cache usages should have the same repository_id"
    end
    if usages.map(&:owner_id).uniq.size != 1
      raise ArgumentError, "All cache usages should have the same owner_id"
    end
    @usages = usages
  end

  sig { returns(T.nilable(::Integer)) }
  memoize def active_caches_size
    if @usages.present? && @usages.first.present?
      @usages.map(&:active_caches_size).sum
    end
  end

  sig { returns(T.nilable(::Integer)) }
  memoize def active_caches_count
    if @usages.present? && @usages.first.present?
      @usages.map(&:active_caches_count).sum
    end
  end

  sig { returns(T.nilable(::ActiveSupport::TimeWithZone)) }
  memoize def created_at
    if @usages.present? && @usages.first.present?
      @usages.map(&:created_at).min
    end
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  memoize def updated_at
    if @usages.present? && @usages.first.present?
      @usages.map(&:updated_at).max
    end
  end

  sig { returns(T.nilable(::Integer)) }
  memoize def repository_id
    if @usages.present? && @usages.first.present?
      T.must(@usages.first).repository_id
    end
  end

  sig { returns(T.nilable(::Integer)) }
  memoize def owner_id
    if @usages.present? && @usages.first.present?
      T.must(@usages.first).owner_id
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  memoize def has_results?
    if @usages.present?
      @usages.any?(&:is_results_usage)
    end
  end
end
