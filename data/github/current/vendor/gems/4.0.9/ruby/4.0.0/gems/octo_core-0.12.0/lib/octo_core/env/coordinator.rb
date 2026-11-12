# typed: strict
# frozen_string_literal: true

module OctoCore
  module Env
    module Coordinator
      extend T::Sig

      sig do
        params(
          env_class: T.class_of(OctoCore::Env::Base),
          name: Symbol,
          type: Symbol,
          default: T.untyped,
          required: T::Boolean,
          prefix: T.nilable(String)
        ).void
      end
      def self.register_env_variable!(env_class, name, type, default, required, prefix)
        var_name = env_variable_name(name, prefix)

        if env_variable_registry.key?(var_name)
          raise ArgumentError, "Environment variable #{var_name} is already defined by #{env_variable_registry[var_name]}"
        end

        env_variable_registry[var_name] = env_class

        if required && ENV[var_name].nil? && default.nil?
          missing_env_variables << var_name
        end
      end

      sig { returns(T::Array[String]) }
      def self.missing_env_variables
        @missing_env_variables ||= T.let([], T.nilable(T::Array[String]))
      end

      sig { params(definition_name: Symbol, prefix: T.nilable(String)).returns(String) }
      def self.env_variable_name(definition_name, prefix)
        "#{prefix}#{definition_name.upcase}"
      end

      sig { returns(T::Hash[String, T.class_of(OctoCore::Env::Base)]) }
      def self.env_variable_registry
        @env_variable_registry ||= T.let({}, T.nilable(T::Hash[String, T.class_of(OctoCore::Env::Base)]))
      end
    end
  end
end
