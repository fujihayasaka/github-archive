# typed: strict
# frozen_string_literal: true

require "octo_core"
require "tapioca/dsl"

module Tapioca
  module Dsl
    module Compilers
      class OctoCoreEnvVariable < Tapioca::Dsl::Compiler
        extend T::Sig
        extend T::Generic

        ConstantType = type_member { { fixed: T.class_of(::OctoCore::Env::Base) } }

        sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
        def self.gather_constants
          OctoCore::Env::Base.descendants
        end

        sig { override.void }
        def decorate
          return if T.unsafe(constant).defined_env_methods.empty?

          root.create_path(constant) do |model|
            model.create_module("GeneratedOctoCoreEnvMethods") do |mod|
              T.unsafe(constant).defined_env_methods.each do |name, method_data|
                return_type, method_name = case method_data[:type]
                when :boolean
                  ["T::Boolean", "#{name}?"]
                when :integer
                  type = method_data[:required] == false && method_data[:default].nil? ? "T.nilable(Integer)" : "Integer"
                  [type, name.to_s]
                when :string
                  type = method_data[:required] == false && method_data[:default].nil? ? "T.nilable(String)" : "String"
                  [type, name.to_s]
                end
                mod.create_method(method_name, return_type: return_type)
              end
            end

            model.create_extend("GeneratedOctoCoreEnvMethods")
          end
        end
      end
    end
  end
end
