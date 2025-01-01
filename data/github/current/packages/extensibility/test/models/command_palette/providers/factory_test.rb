# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class ProvidersFactoryTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
      end

      setup do
        @context = Context.new(current_user: @user)
      end

      test "returns nil for unkown provider" do
        assert_nil Factory.build(:unkown, nil)
      end

      test "returns nil for disabled providers" do
        disabled_providers = Factory::PROVIDERS.reject { |_, klass| klass.enabled?(@context) }

        disabled_providers.each do |provider_factory_id, _provider_type|
          assert_nil Factory.build(provider_factory_id, @context)
        end
      end

      test "returns a provider class for every provider" do
        enabled_providers = Factory::PROVIDERS.select { |_, klass| klass.enabled?(@context) }

        enabled_providers.each do |provider_factory_id, _provider_type|
          provider = Factory.build(provider_factory_id, @context)
          assert_expected_type(provider_factory_id, provider, ApplicationProvider)
        end
      end
    end
  end
end
