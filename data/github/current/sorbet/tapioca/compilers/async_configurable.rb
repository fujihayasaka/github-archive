# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    # The Configurable::Async module provides Configurable modules the ability
    # to load configuration values asynchronously before executing the defined method
    # This compiler finds all uses of Configurable::Async and generates RBI files for the async methods.
    #
    # Example:
    # ~~~rb
    # module Configurable
    #   module SomeConfiguration
    #     KEY = "feature_on".freeze
    #
    #     extend T::Helpers
    #     extend Configurable::Async
    #
    #     requires_ancestor { Configurable }
    #
    #     sig { returns(T::Boolean) }
    #     def feature_on?
    #       config.enabled?(KEU)
    #     end
    #     async_configurable :feature_on?
    #   end
    # end
    # ~~~
    #
    # Generates the following RBI file:
    #
    # ~~~rb
    # module Configurable::SomeConfiguration
    #   include GeneratedAsyncConfigurableMethods
    #
    #   module GeneratedAsyncConfigurableMethods
    #     sig { returns(Promise[T::Boolean]) }
    #     def async_feature_on?; end
    #   end
    # end
    # ~~~
    class AsyncConfigurable < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.all(Module, ::Configurable::Async) } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        all_modules.select { |c| c.singleton_class < ::Configurable::Async }
      end

      sig { override.void }
      def decorate
        return if constant.async_configurable_methods.empty?

        root.create_path(constant) do |model|
          model.create_module("GeneratedAsyncConfigurableMethods") do |mod|
            constant.async_configurable_methods.each do |name|
              method_name = "async_#{name}"
              return_type = T::Utils.signature_for_method(constant.instance_method(name))&.return_type&.to_s || "T.untyped"

              mod.create_method(method_name, return_type: "Promise[#{return_type}]")
            end
          end

          model.create_include("GeneratedAsyncConfigurableMethods")
        end
      end
    end
  end
end
