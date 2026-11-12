# typed: strict
# frozen_string_literal: true

require "octo_core"

module Tapioca
  module Extensions
    module OctoCoreEnvExtension
      extend T::Sig

      sig { params(name: Symbol, type: Symbol, default: T.untyped, required: T::Boolean).void }
      def define_env_variable(name, type, default: nil, required: false)
        super

        defined_env_methods[name] = { type:, default:, required: }
      end

      sig { returns(T::Hash[Symbol, T::Hash[Symbol, T.anything]]) }
      def defined_env_methods
        @defined_env_methods ||= T.let({}, T.nilable(T::Hash[Symbol, T::Hash[Symbol, T.anything]]))
      end
    end
  end
end

OctoCore::Env::Base.singleton_class.prepend(Tapioca::Extensions::OctoCoreEnvExtension)
