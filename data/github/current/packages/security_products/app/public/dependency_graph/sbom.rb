# typed: strict
# frozen_string_literal: true

# This is the public interface for the SBOM generation service that Dependency Graph provides to the monolith.
#
# NOTE: At time of writing, much of the code used by these interfaces is public and can be called directly but this
# is an initial effort at establishing a package interface so we can make them private in the near future.
#   see: https://github.com/github/dependency-graph/pull/5751
#
module DependencyGraph
  module SBOM
    class SBOMFile < T::Struct
      prop :filename, String
      prop :contents, String
    end

    class SBOMResult < T::Struct
      prop :status, Symbol
      prop :sbom_url, T.nilable(String)
      prop :deadline, T.nilable(Time)
      prop :user_error_message, T.nilable(String)
    end

    class SBOMNotFoundError < StandardError; end
    class SBOMRequestError < StandardError; end # Raised for any remote service exception
    class SBOMTimeoutError < StandardError; end # Raised on client-side timeout

    # Provides access to asynchronous SBOM generation, the report manager needs to be
    # initialised with a target repository and user so we can perform caching on the
    # user if necessary.
    class ReportManager
      include GitHub::Memoizer

      ANON_ACCESS_CACHE_KEY_PREFIX = T.let("dg:sbom:generate_sbom:anon", String)
      ANON_ACCESS_CACHE_TTL = T.let(15.minutes, ActiveSupport::Duration)

      USER_ACCESS_CACHE_KEY_PREFIX = T.let("dg:sbom:generate_sbom:user", String)
      USER_ACCESS_CACHE_TTL = T.let(1.second, ActiveSupport::Duration)

      sig { returns(Repository) }
      attr_reader :repo

      sig { returns(T.nilable(User)) }
      attr_reader :user

      sig { params(repo: Repository, user: T.nilable(User)).void }
      def initialize(repo:, user:)
        @repo = repo
        @user = T.let(user, T.nilable(User))
      end

      sig { returns(String) }
      def generate_sbom
        if user
          # If the user is set, cache the uuid to prevent abuse without restricting
          # fresh report generation perceptibly.
          GitHub.cache.fetch(user_cache_key, ttl: USER_ACCESS_CACHE_TTL) do
            sbomer.create_sbom
          end
        else
          # If we are dealing with anonymous access, cache the uuid to limit
          # report generation aggressively for the public internet.
          GitHub.cache.fetch(anon_cache_key, ttl: ANON_ACCESS_CACHE_TTL) do
            sbomer.create_sbom
          end
        end
      end

      sig { params(sbom_uuid: String, signed_link_ttl_minutes: Integer).returns(SBOMResult) }
      def fetch_sbom(sbom_uuid:, signed_link_ttl_minutes: DependencyGraphPlatform::Twirp::SbomClient::DEFAULT_SIGNED_LINK_TTL_MINUTES)
        sbomer.get_sbom_result(sbom_uuid:, signed_link_ttl_minutes:)
      end

      sig { params(sbom_uuid: String).returns(SBOMResult) }
      def poll_sbom_readiness(sbom_uuid:)
        sbomer.poll_sbom_result(sbom_uuid:)
      end

      private

      sig { returns(String) }
      memoize def anon_cache_key
        [
          ANON_ACCESS_CACHE_KEY_PREFIX,
          "repo",
          repo.id
        ].join(":")
      end

      sig { returns(String) }
      memoize def user_cache_key
        [
          USER_ACCESS_CACHE_KEY_PREFIX,
          T.must(user).id,
          "repo",
          repo.id
        ].join(":")
      end

      sig { returns(Sbomer) }
      memoize def sbomer
        Sbomer.new(repo)
      end
    end

    # TODO: Verify if we always return a nilable string from both clients
    sig { params(repository: Repository, ghes: T::Boolean).returns(SBOMFile) }
    def self.get_sbom_for_repository(repository, ghes: false)
      Sbomer.new(repository, ghes:).get_sbom
    end
  end
end
