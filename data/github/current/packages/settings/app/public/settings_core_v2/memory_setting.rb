# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # In memory implementation of ISetting.
  # This is used for constructing settings from the API/UI
  # or for non-persistent setting objects
  class MemorySetting
    include ISetting

    sig { override.returns(T.untyped) }
    attr_reader :resource

    sig { override.returns(T::Array[SettingsCoreV2::IRule]) }
    attr_reader :rules

    sig { override.returns(String) }
    attr_reader :name

    sig { override.returns(T.untyped) }
    attr_reader :value

    sig { params(value: T.untyped).void }
    attr_writer :value

    sig { override.returns(T.nilable(Integer)) }
    attr_reader :id

    sig { params(name: String, value: T.untyped, resource: T.untyped, rules: T::Array[IRule], id: T.nilable(Integer)).void }
    def initialize(name, value, resource, rules = [], id: nil)
      @name = name
      @value = value
      @resource = resource
      @rules = rules
      @id = id

      @rules.each { |r| r.setting = self if r.is_a?(MemoryRule) }
    end

    sig { params(setting: ISetting).returns(MemorySetting) }
    def self.from_interface(setting)
      MemorySetting.new(
        setting.name,
        setting.value,
        setting.resource,
        setting.rules.map { |r| MemoryRule.from_interface(r) },
        id: setting.respond_to?(:id) ? setting.id : nil,
      )
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      other.is_a?(MemorySetting) &&
        name == other.name &&
        value == other.value &&
        rules == other.rules &&
        id == other.id || false
    end

    sig { params(hash: T::Hash[String, T.untyped], resource: T.untyped).returns(MemorySetting) }
    def self.from_hash(hash, resource)
      MemorySetting.new(
        hash.fetch("name"),
        hash.fetch("value"),
        resource,
        hash.fetch("rules", []).map { |r| MemoryRule.from_hash(r) },
        id: (id = hash["id"]).is_a?(Integer) && id > 0 ? id : nil,
      )
    end
  end
end
