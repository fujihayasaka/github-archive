# typed: strict
# frozen_string_literal: true

# This module defines the interfaces of several DependabotGraph objects that are used in the context of
# Dependabot Alerts.
#
# The DependencyGraph module tends towards defining generic objects for data from the legacy dependency service
# that are used in multiple contexts. Our replacement service prefers to implement each access pattern in isolation
# so the DependencyGraphPlatform module will have objects that only implement a narrow subset of the DependencyGraph
# equivalent.
#
# The intent of these interfaces is to:
# - Strictly define the subset of methods on generic DependancyGraph objects that are used in the alerting context
# - Verify that their DependencyGraphPlatform equivalents can be used interchangeably as they implement the same
#   contract
#
# This will give us better guarantees that the implementations cannot drift until we have completed migration off
# the legacy service.
module DependencyGraph
  module Alerting
    # AlertableDependents are used during Advisory alerting, each representing a single detection of a vulnerable
    # version range
    module AlertableDependent
      extend T::Helpers
      abstract!

      sig { abstract.returns(Integer) }
      def repository_id; end

      sig { abstract.returns(String) }
      def manifest_path; end

      sig { abstract.returns(String) }
      def requirements; end

      sig { abstract.returns(String) }
      def scope; end

      sig { abstract.returns(T.nilable(String)) }
      def relationship; end

      sig { abstract.returns(T.nilable(Integer)) }
      def dgp_dependency_id; end

      # lib/hydro/schemas/dependabot/v0/entities/dependency_scope_pb.rb
      sig { returns(Symbol) }
      def scope_to_hydro_enum
        case scope.to_s.downcase
        when "runtime"
          :RUNTIME
        when "development"
          :DEVELOPMENT
        else
          :UNKNOWN
        end
      end

      # lib/hydro/schemas/dependabot/v0/entities/dependency_relationship_pb.rb
      sig { returns(Symbol) }
      def relationship_to_hydro_enum
        case relationship.to_s.downcase
        when "direct"
          :DIRECT
        when "transitive"
          :INDIRECT # TODO: Update the protobuf to align on transitive
        when "inconclusive"
          :INCONCLUSIVE
        else
          :UNKNOWN_DEPENDENCY_RELATIONSHIP
        end
      end

      sig { returns(T.nilable(Integer)) }
      def dgp_dependency_id_to_hydro
        return nil unless dgp_dependency_id.to_i > 0

        dgp_dependency_id
      end
    end

    # AlertableManifests are used during Repository alerting, each representing a single manifest detected within
    # the repository at the SHA requested.
    module AlertableManifest
      extend T::Helpers
      abstract!

      sig { abstract.returns(String) }
      def logical_path; end

      sig { abstract.returns(T::Boolean) }
      def vendored?; end

      sig { abstract.params(other: AlertableManifest).returns(T.nilable(T::Boolean)) }
      def supersedes?(other); end

      sig { abstract.returns(T::Array[AlertableDependency]) }
      def dependencies; end
    end

    # AlertableDependencies are used during Repository alerting, each representing a single detected dependency.
    module AlertableDependency
      extend T::Helpers
      abstract!

      module VulnerableVersionRange
        extend T::Helpers
        abstract!

        sig { abstract.returns(T::Boolean) }
        def contained?; end

        sig { abstract.returns(Integer) }
        def github_id; end
      end

      sig { abstract.returns(T.nilable(Integer)) }
      def repository_id; end

      sig { abstract.returns(String) }
      def requirements; end

      sig { abstract.returns(T.nilable(String)) }
      def scope; end

      sig { abstract.returns(String) }
      def relationship; end

      sig { abstract.returns(T::Array[VulnerableVersionRange]) }
      def vulnerable_version_ranges; end
    end
  end
end
