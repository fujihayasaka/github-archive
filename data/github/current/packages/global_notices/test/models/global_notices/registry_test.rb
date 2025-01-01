# typed: true
# frozen_string_literal: true

require "test_helper"

module GlobalNoticesTest
  # TODO: This could be a unit test if we supported them in domains (or at all)
  class RegistryTest < GitHub::TestCase
    setup do
      @registry = GlobalNotices::Registry.new
    end

    sig { returns(GlobalNotices::Registry) }
    attr_reader :registry

    test "raises when a notice with the same name is already registered" do
      registry.register(:foo) { |_| true }
      assert_raises(ArgumentError) do
        registry.register(:foo) { |_| true }
      end
    end

    test "any notice name supercedes :no_notice" do
      registry.register(:foo) { |_| true }
      assert registry.supercedes_notice?(new_name: :foo, current_name: :no_notice)
    end

    test "notices should be registered in priority order" do
      registry.register(:bar) { |_| true }
      registry.register(:baz) { |_| true }
      registry.register(:qux) { |_| true }
      registry.register(:mona) { |_| true }

      assert registry.supercedes_notice?(new_name: :bar, current_name: :baz)
      assert registry.supercedes_notice?(new_name: :baz, current_name: :qux)
      assert registry.supercedes_notice?(new_name: :qux, current_name: :mona)
      assert registry.supercedes_notice?(new_name: :bar, current_name: :mona)

      refute registry.supercedes_notice?(new_name: :mona, current_name: :qux)
      refute registry.supercedes_notice?(new_name: :qux, current_name: :baz)
      refute registry.supercedes_notice?(new_name: :baz, current_name: :bar)
    end
  end
end
