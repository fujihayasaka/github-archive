# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AlertableManifest < T::Struct
    include DependencyGraph::Alerting::AlertableManifest

    ROOT_PATH = T.let(".".freeze, String)

    prop :path, String
    prop :name, String
    prop :dependencies, T::Array[AlertableDependency], default: []

    sig { returns(String) }
    def manifest_type
      name.gsub(/-|\./, "_")
    end

    sig { override.returns(String) }
    def logical_path
      return name if path == ROOT_PATH

      File.join(path, name)
    end

    # The alerting process filters out any vendored manifests returned by Dependency Graph API,
    # but in the case of Dependency Graph Platform vendored manifests are filtered out at
    # ingestion, so this is always false.
    sig { override.returns(T::Boolean) }
    def vendored?
      false
    end

    sig { override.params(other: T.untyped).returns(T::Boolean) }
    def supersedes?(other)
      return false unless other.is_a?(self.class)
      return false unless other.path == path

      DependencyGraph::Manifest::SUPERSEDED_BY[other.manifest_type]&.include?(manifest_type) || false
    end
  end
end
