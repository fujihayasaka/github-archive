# typed: strict
# frozen_string_literal: true

module SettingsCore
  class MemorySetting
    include ISetting

    sig { override.returns(Targeting::Targetable) }
    attr_reader :targetable

    sig { override.returns(T::Array[SettingsCore::IRule]) }
    attr_reader :rules

    sig { override.returns(String) }
    attr_reader :name

    sig { override.returns(T.untyped) }
    attr_reader :value

    sig { override.returns(String) }
    attr_reader :provider_name

    sig { override.returns(T.nilable(Integer)) }
    attr_reader :id

    sig { params(name: String, value: T.untyped, targetable: Targeting::Targetable, provider_name: String, rules: T::Array[IRule], id: T.nilable(Integer)).void }
    def initialize(name, value, targetable, provider_name, rules = [], id: nil)
      @name = name
      @value = value
      @targetable = targetable
      @provider_name = provider_name
      @rules = rules
      @id = id

      @rules.each { |r| r.setting = self if r.is_a?(MemoryRule) }
    end

    sig { params(hash: T::Hash[String, T.untyped], provider: String, targetable: Targeting::Targetable).returns(MemorySetting) }
    def self.from_hash(hash, provider, targetable)
      MemorySetting.new(
        hash.fetch("name"),
        hash.fetch("value"),
        targetable,
        provider,
        hash.fetch("rules", []).map { |r| MemoryRule.from_hash(r) },
        id: hash["id"].present? && hash["id"] > 0 ? hash["id"] : nil,
      )
    end
  end
end
