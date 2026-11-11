# typed: strict
# frozen_string_literal: true

module Repositories::Cache::Shared
  MAX_TTL_SECONDS = T.let(12.hours.in_seconds, Integer)
  MIN_TTL_SECONDS = 5

  extend T::Helpers

  requires_ancestor { GitHub::RemoteCache::Preset::DisableIfRecentDatabaseWrite }

  sig { returns(T.nilable(T::Array[T.class_of(ApplicationRecord::Base)])) }
  def disable_on_writes_to
    [ApplicationRecord::Repositories]
  end
end
