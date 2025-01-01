# typed: strict
# frozen_string_literal: true

require "vexi"
require "vexi/adapters/in_memory_adapter"
require_relative "./config"

module FeatureFlag
  extend T::Helpers

  @config = T.let(nil, T.nilable(FeatureFlag::Config))
  @vexi_test_adapter = T.let(nil, T.nilable(Vexi::Adapters::InMemoryAdapter))

  sig { returns(Vexi::Client) }
  def self.vexi
    config.vexi_instance
  end

  sig { returns(T.nilable(Vexi::Adapters::InMemoryAdapter)) }
  def self.vexi_test_adapter
    @vexi_test_adapter ||= config.vexi_test_adapter
  end

  sig { returns(T.nilable(FeatureFlag::Cache::IMemcachedClient)) }
  def self.cache_client
    config.cache_client
  end

  sig { returns(FeatureFlag::Config) }
  private_class_method def self.config
    @config ||= FeatureFlag::Config.new
  end
end
