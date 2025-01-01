# typed: strict
# frozen_string_literal: true

class MagicShell
  module Strategies
    class Base
      extend T::Sig
      extend T::Helpers
      extend T::Generic
      abstract!

      CACHE_TTL = T.let(10.minutes.freeze, Integer)

      DataTypeValue = type_member

      # Denormalized at the user level, so cached/denormalized data _does
      # not_ depend on the repository.
      class ViewerContext < Base
        extend T::Helpers
        abstract!

        DataTypeValue = type_member

        sig { abstract.params(viewer: T.nilable(::User)).returns(T.untyped) }
        def precomputed(viewer); end
      end

      # Denormalized at the repository level, so cached/denormalized data _does
      # not_ depend on the viewer.
      class RepositoryContext < Base
        extend T::Helpers
        abstract!

        DataTypeValue = type_member

        sig { abstract.params(repository: T.nilable(::Repository)).returns(T.untyped) }
        def precomputed(repository); end
      end

      sig { abstract.void }
      def self.data_type; end

      sig { params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def call(viewer, repository)
        if can_use_precomputed_data?(viewer, repository)
          fetch_precomputed_data(viewer, repository)
        else # assumes that we aren't handling repo+user data
          GitHub.dogstats.distribution_time("magic_shell.fallback.duration", tags: stats_tags) do
            fetch_live_data(viewer, repository)
          end
        end
      rescue StandardError => e
        raise if GitHub::AppEnvironment.development?

        Failbot.report(e)
        GitHub.dogstats.increment("magic_shell.gracefully_degraded", tags: stats_tags)

        gracefully_degraded_data
      end

      sig { params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_precomputed_data(viewer, repository)
        cache_hit = T.let(true, T::Boolean)
        result = GitHub.cache.fetch(cache_key(viewer, repository), ttl: CACHE_TTL) do
          GitHub.dogstats.distribution_time("magic_shell.precomputed.duration", tags: stats_tags) do
            cache_hit = false
            if is_a?(ViewerContext)
              precomputed(viewer)
            elsif is_a?(RepositoryContext)
              precomputed(repository)
            end
          end
        end

        GitHub.dogstats.increment("magic_shell.cache.#{cache_hit ? "hit" : "miss"}", tags: stats_tags)

        result
      end

      sig { params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(String) }
      def cache_key(viewer, repository)
        key_parts = [
          "magic_shell",
          "v1",
          T.must(self.class.name).underscore.gsub("/", "__"),
        ]

        if is_a?(ViewerContext)
          key_parts << viewer&.id.to_i
        elsif is_a?(RepositoryContext)
          key_parts << T.must(repository).id
        end

        key_parts.join(":")
      end

      sig { returns(T::Array[String]) }
      def stats_tags
        ["strategy:#{self.class.name}"].tap do |tags|
          if is_a?(ViewerContext)
            tags << "context:viewer"
          elsif is_a?(RepositoryContext)
            tags << "context:repository"
          end
        end
      end

      sig { abstract.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(T::Boolean) }
      def can_use_precomputed_data?(viewer, repository); end

      sig { abstract.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_live_data(viewer, repository); end

      # this method is used to return a value when an exception occurs when
      # trying to fetch precomputed or live data.
      sig { abstract.returns(DataTypeValue) }
      def gracefully_degraded_data; end

    end
  end
end
