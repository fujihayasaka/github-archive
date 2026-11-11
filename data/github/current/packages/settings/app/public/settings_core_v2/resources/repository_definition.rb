# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Resources
    class RepositoryDefinition < ResourceDefinition
      sig { params(configurable: T::Boolean, inherit_org: T::Boolean).void }
      def initialize(configurable: true, inherit_org: true)
        super(ResourceType::REPOSITORY, configurable: configurable)
        @inherit_org = inherit_org
      end

      sig { override.params(resource: T.untyped).returns(T::Boolean) }
      def is_resource?(resource)
        resource.is_a?(Repository)
      end

      sig { override.returns(T::Array[ConditionMatcher]) }
      def matchers
        [
          SettingsCoreV2::Conditions::RepositoryNameMatcher.new,
          SettingsCoreV2::Conditions::RepositoryCustomPropertyMatcher.new,
          SettingsCoreV2::Conditions::RepositoryIdMatcher.new,
        ]
      end

      sig { override.params(repository: T.untyped).returns(T::Array[T.untyped]) }
      def parents(repository)
        return [] unless @inherit_org
        if repository.is_a?(Repository) && (owner = repository.owner).is_a?(Organization)
          [owner]
        else
          []
        end
      end

      sig { override.params(resource: T.untyped).returns(T::Array[T.untyped]) }
      def children(resource)
        []
      end

      sig { override.params(resource: T.untyped).returns(T::Hash[String, T.untyped]) }
      def ui_payload(resource)
        return {} unless resource.is_a?(Repository)
        owner = resource.owner
        {
          id: resource.id,
          nodeId: resource.global_relay_id,
          type: "Repository",
          name: resource.name,
          ownerLogin: owner&.display_login,
          visibility: resource.visibility,
        }
      end

      sig { override.params(id: T.any(String, Integer), parent: T.untyped).returns(T.untyped) }
      def from_id(id, parent: nil)
        if parent
          parent.repositories.find_by(id: id)
        else
          Repository.find_by(id: id)
        end
      end
    end
  end
end
