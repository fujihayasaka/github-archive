# typed: true
# frozen_string_literal: true

module DependencySnapshot
  module EntitySerializer
    autoload :Push, "dependency_snapshot/entity_serializer/push"
    autoload :Repository, "dependency_snapshot/entity_serializer/repository"
    autoload :User, "dependency_snapshot/entity_serializer/user"
  end
end
