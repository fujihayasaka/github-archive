# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AlertableDependent < T::Struct
    include DependencyGraph::Alerting::AlertableDependent

    ROOT_PATH = T.let(".".freeze, String)

    prop :repository_id, Integer, override: :reader
    prop :path, String
    prop :filename, String
    prop :requirements, String, override: :reader
    prop :scope, String, override: :reader
    prop :relationship, String, override: :reader
    prop :dgp_dependency_id, T.nilable(Integer), default: nil, override: :reader

    sig { override.returns(String) }
    def manifest_path
      return filename if path == ROOT_PATH

      File.join(path, filename)
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      !!(other.is_a?(AlertableDependent) &&
        other.repository_id == repository_id &&
        other.manifest_path == manifest_path &&
        other.requirements == requirements &&
        other.scope == scope &&
        other.relationship == relationship &&
        other.dgp_dependency_id == dgp_dependency_id)
    end
  end
end
