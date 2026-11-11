# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AlertableDependency < T::Struct
    include DependencyGraph::Alerting::AlertableDependency

    class VulnerableVersionRange < T::Struct
      include DependencyGraph::Alerting::AlertableDependency::VulnerableVersionRange

      prop :github_id, Integer, override: :reader

      # DGP responses should filter the vulnerable version ranges returned on a dependency to only
      # those which contain the dependency's requirements, so this will always be true
      sig { override.returns(T::Boolean) }
      def contained?
        true
      end
    end

    prop :repository_id, Integer, override: :reader
    prop :requirements, String, override: :reader
    prop :scope, String, override: :reader
    prop :relationship, String, override: :reader
    prop :vulnerable_version_ranges, T::Array[VulnerableVersionRange], default: [], override: :reader
  end
end
