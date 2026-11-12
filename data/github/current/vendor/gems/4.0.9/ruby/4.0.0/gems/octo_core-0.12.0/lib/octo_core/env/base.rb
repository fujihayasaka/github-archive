# typed: strict
# frozen_string_literal: true

module OctoCore
  module Env
    # A base class for immutably accessing environment variables.
    # Variable names are expected to be upper case with the associated prefix (default "GH_").
    # so a variable named "host_name" will be accessed via the environment
    # variable "GH_HOST_NAME".
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Hash[String, T.untyped]) }
      def self.env_variable_store
        @__env_variable_store ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
      end

      # Define a new environment variable that can be accessed via a method on
      # this class. The method will be named after the variable, and will
      # return the value of the variable if it is set, or the default value
      # passed to this method if it is not.
      #
      # name - The Symbol name of the method and the String environment variable. The
      #        method will be defined as an instance method on this module. It will have '?'
      #        appended to it if the type is :boolean. The environment variable will be
      #        prefixed with the prefix argument (default "GH_").
      # type - The Symbol type of the environment variable. Must be one of
      #       :boolean, :string, or :integer.
      # default - The default value to use if the environment variable is not set.
      # required - A Boolean indicating whether the environment variable is required to be set.
      #            If a variable is required but not set, an exception will be raised when it is accessed.
      sig { params(name: Symbol, type: Symbol, default: T.untyped, required: T::Boolean).void }
      def self.define_env_variable(name, type, default: nil, required: false)
        method_name = name

        if type == :boolean
          method_name = "#{name}?"
          raise ArgumentError, "default value must be a boolean" unless [true, false].include?(default)
        elsif type == :string
          raise ArgumentError, "default value must be a string or nil" unless default.nil? || default.is_a?(String)
        elsif type == :integer
          raise ArgumentError, "default value must be an integer or nil" unless default.nil? || default.is_a?(Integer)
        end

        var_name = OctoCore::Env::Coordinator.env_variable_name(name, _env_variable_prefix)

        define_singleton_method(method_name) do
          return env_variable_store[var_name] if env_variable_store.key?(var_name)

          value = if ENV.key?(var_name)
                    v = ENV[var_name].presence
                    case type
                    when :integer
                      Integer(v) # intentionally raise on bad values
                    when :boolean
                      v = v == "true"
                    else
                      v
                    end
                  else
                    default
                  end

          raise ArgumentError, "#{name} is required but not specified in the environment and has no default value" if required && value.nil?

          env_variable_store[var_name] = value
        end

        OctoCore::Env::Coordinator.register_env_variable!(self, name, type, default, required, _env_variable_prefix)
      end

      class_attribute :_env_variable_prefix, default: "GH_", instance_accessor: false

      sig { params(prefix: T.nilable(String)).void }
      def self.prefix_env_variables_with(prefix)
        self._env_variable_prefix = prefix
      end
    end
  end
end
