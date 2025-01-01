# typed: strict
# frozen_string_literal: true

require "vexi"
require "vexi/adapters/in_memory_adapter"
require_relative "./config"
require_relative "./vexi_proxy"

module FeatureFlag
  extend T::Helpers
  extend T::Sig

  @config = T.let(nil, T.nilable(FeatureFlag::Config))
  @vexi_instance = T.let(nil, T.nilable(FeatureFlag::VexiProxy))
  @vexi_test_adapter = T.let(nil, T.nilable(Vexi::Adapters::InMemoryAdapter))

  sig { returns(FeatureFlag::VexiProxy) }
  def self.vexi
    @vexi_instance ||= VexiProxy.new(->() { config.vexi_instance })
  end

  sig { returns(T.nilable(Vexi::Adapters::InMemoryAdapter)) }
  def self.vexi_test_adapter
    @vexi_test_adapter ||= config.vexi_test_adapter
  end

  sig { returns(FeatureFlag::Config) }
  private_class_method def self.config
    @config ||= FeatureFlag::Config.new
  end
end
