# typed: strict
# frozen_string_literal: true

require "feature_flag/adapters/test_adapter"
require "vexi"
require "vexi_management"
require_relative "./config"
require_relative "./observability"

module FeatureFlag
  extend T::Helpers

  @config = T.let(nil, T.nilable(FeatureFlag::Config))
  @observability = T.let(nil, T.nilable(FeatureFlag::Observability))

  sig { returns(Vexi::Client) }
  def self.vexi
    config.vexi_instance
  end

  sig { returns(VexiManagement::Client) }
  def self.vexi_management
    config.vexi_management_instance
  end

  sig { returns(T.nilable(FeatureFlag::Cache::IMemcachedClient)) }
  def self.cache_client
    config.cache_client
  end

  sig { void }
  def self.reset_vexi_data
    adapter = T.unsafe(config.vexi_data_adapter)
    if adapter.respond_to?(:reset)
      adapter.reset
    else
      raise "vexi_data_adapter does not implement #reset"
    end
  end

  sig { params(pattern: String, enabled: T::Boolean).void }
  def self.add_vexi_override(pattern, enabled:)
    return if pattern.empty?
    overrides[pattern] = enabled
  end

  sig { void }
  def self.clear_vexi_overrides
    Thread.current[:vexi_overrides] = {}
  end

  sig { void }
  def self.update_vexi_config
    @config = nil
  end

  sig { returns(FeatureFlag::Config) }
  private_class_method def self.config
    @config ||= FeatureFlag::Config.new
    @observability ||= FeatureFlag::Observability.new
    @config
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  private_class_method def self.overrides
    Thread.current[:vexi_overrides] ||= {}
  end
end
