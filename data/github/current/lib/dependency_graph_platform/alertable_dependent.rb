# typed: strict
# frozen_string_literal: true

module DependencyGraphPlatform
  class AlertableDependent < T::Struct
    include DependencyGraph::Alerting::AlertableDependent

    prop :repository_id, Integer
    prop :manifest_path, String
    prop :requirements, String
    prop :scope, String
    prop :relationship, String
    prop :dgp_dependency_id, T.nilable(Integer), default: nil

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
