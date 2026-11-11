# typed: strict
# frozen_string_literal: true

module GitHub
  # Represents a per-request override for the remote cache behavior.
  #
  # - `None`:         Normal caching behavior (default).
  # - `Skip`:         Bypass the remote cache entirely for this request.
  # - `ForceRefresh`: Force-refresh all remote cache keys for this request.
  #
  # NOTE: This lives at the `GitHub::` namespace (rather than under
  # `GitHub::RemoteCache`) to avoid forcing the entire `GitHub::RemoteCache`
  # module (and its ActiveRecord-dependent transitive requires) to load when
  # this enum is referenced from lightweight code paths such as `GH::Context`.
  # If it lived at `GitHub::RemoteCache::Override`, merely opening
  # `module GitHub::RemoteCache` in this file would trigger Zeitwerk to
  # autoload `lib/github/remote_cache.rb`, which eagerly requires the heavy
  # client stack.
  class RemoteCacheOverride < T::Enum
    enums do
      None = new
      Skip = new
      ForceRefresh = new
    end
  end
end
