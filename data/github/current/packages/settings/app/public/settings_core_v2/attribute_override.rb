# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class AttributeOverride < T::Struct
    const :resource, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :attribute, String
    const :override, T.nilable(T.any(String, T::Array[String]))

    sig { params(resource_def: ResourceDefinition).returns(T::Hash[String, T.untyped]) }
    def to_hash(resource_def)
      {
        "resource_id" => resource.id,
        "resource_type" => resource_def.resource_type.serialize,
        "attribute" => attribute,
        "override" => override,
      }
    end

    sig do
      params(
        hash: T::Hash[String, T.untyped],
        setting_definition: SettingDefinition[T.untyped, T.untyped],
      ).returns(T.nilable(AttributeOverride))
    end
    def self.from_hash(hash, setting_definition)
      resource_def = setting_definition.resource_definitions.find { |rd| rd.resource_type.serialize == hash["resource_type"] }
      return nil unless resource_def
      resource = resource_def.from_id(hash["resource_id"])
      return nil unless resource
      new(resource:, attribute: hash["attribute"], override: hash["override"])
    end
  end
end
