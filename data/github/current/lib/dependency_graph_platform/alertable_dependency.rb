# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AlertableDependency < T::Struct
    include DependencyGraph::Alerting::AlertableDependency

    class VulnerableVersionRange < T::Struct
      include DependencyGraph::Alerting::AlertableDependency::VulnerableVersionRange

      prop :github_id, Integer

      # DGP responses should filter the vulnerable version ranges returned on a dependency to only
      # those which contain the dependency's requirements, so this will always be true
      sig { override.returns(T::Boolean) }
      def contained?
        true
      end
    end

    prop :repository_id, Integer
    prop :requirements, String
    prop :scope, String
    prop :relationship, String
    prop :vulnerable_version_ranges, T::Array[VulnerableVersionRange], default: []
  end
end
