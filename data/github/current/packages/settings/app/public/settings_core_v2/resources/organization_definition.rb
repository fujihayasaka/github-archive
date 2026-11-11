# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Resources
    class OrganizationDefinition < ResourceDefinition
      sig { params(configurable: T::Boolean, inherit_business: T::Boolean).void }
      def initialize(configurable: true, inherit_business: true)
        super(ResourceType::ORGANIZATION, configurable: configurable)
        @inherit_business = inherit_business
      end

      sig { override.params(resource: T.untyped).returns(T::Boolean) }
      def is_resource?(resource)
        resource.is_a?(Organization)
      end

      sig { override.returns(T::Array[ConditionMatcher]) }
      def matchers
        [
          SettingsCoreV2::Conditions::OrganizationNameMatcher.new,
        ]
      end

      sig { override.params(organization: T.untyped).returns(T::Array[T.untyped]) }
      def parents(organization)
        return [] unless organization.is_a?(Organization) && @inherit_business
        [organization.business].compact
      end

      sig { override.params(resource: T.untyped).returns(T::Array[T.untyped]) }
      def children(resource)
        if resource.is_a?(Organization)
          resource.repositories.to_a
        else
          []
        end
      end

      sig { override.params(resource: T.untyped).returns(T::Hash[String, T.untyped]) }
      def ui_payload(resource)
        return {} unless resource.is_a?(Organization)
        {
          id: resource.id,
          type: "Organization",
          name: resource.display_login,
          primaryAvatarUrl: resource.primary_avatar_url,
        }
      end

      sig { override.params(id: T.any(String, Integer), parent: T.untyped).returns(T.untyped) }
      def from_id(id, parent: nil)
        if parent
          parent.organizations.find_by(id: id)
        else
          Organization.find_by(id: id)
        end
      end
    end
  end
end
