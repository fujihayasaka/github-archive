# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class ResourceDefinition
    extend T::Helpers

    abstract!

    sig { returns(ResourceType) }
    attr_reader :resource_type

    sig { returns(T::Boolean) }
    attr_reader :configurable

    sig { params(resource_type: ResourceType, configurable: T::Boolean).void }
    def initialize(resource_type, configurable: true)
      @resource_type = resource_type
      @configurable = configurable
    end

    sig { abstract.params(resource: T.untyped).returns(T::Boolean) }
    def is_resource?(resource); end

    sig { abstract.returns(T::Array[ConditionMatcher]) }
    def matchers; end

    sig { abstract.params(resource: T.untyped).returns(T::Array[T.untyped]) }
    def parents(resource); end

    sig { abstract.params(resource: T.untyped).returns(T::Array[T.untyped]) }
    def children(resource); end

    sig { abstract.params(resource: T.untyped).returns(T::Hash[String, T.untyped]) }
    def ui_payload(resource); end

    sig { abstract.params(id: T.any(String, Integer), parent: T.untyped).returns(T.untyped) }
    def from_id(id, parent: nil); end

    class ResourceType < T::Enum
      enums do
        REPOSITORY = new("Repository")
        ORGANIZATION = new("Organization")
        BUSINESS = new("Business")
        USER = new("User")
      end
    end
  end
end
