# typed: strict
# frozen_string_literal: true

require "feature_flag/adapters/test_adapter"
require "vexi"
require_relative "./config"

module FeatureFlag
  extend T::Helpers

  @config = T.let(nil, T.nilable(FeatureFlag::Config))
  @vexi_test_adapter = T.let(nil, T.nilable(FeatureFlag::Adapters::TestAdapter))

  sig { returns(Vexi::Client) }
  def self.vexi
    config.vexi_instance
  end

  sig { returns(FeatureFlag::Adapters::TestAdapter) }
  def self.vexi_test_adapter
    @vexi_test_adapter ||= config.vexi_test_adapter
  end

  sig { returns(T.nilable(FeatureFlag::Cache::IMemcachedClient)) }
  def self.cache_client
    config.cache_client
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

  sig { returns(FeatureFlag::Config) }
  private_class_method def self.config
    @config ||= FeatureFlag::Config.new
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  private_class_method def self.overrides
    Thread.current[:vexi_overrides] ||= {}
  end
end
