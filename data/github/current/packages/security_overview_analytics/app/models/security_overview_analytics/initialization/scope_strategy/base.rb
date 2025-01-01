# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class Initialization
    module ScopeStrategy
      class Base
        extend T::Sig
        extend T::Helpers
        include GitHub::Memoizer

        abstract!

        sig { returns(T::Array[SecurityOverviewAnalytics::Initialization::Type]) }
        def initialization_types
          self.class.available_initialization_types
        end

        sig { abstract.params(id: Integer, prerequisite: T.nilable(Type)).returns(String) }
        def self.initialization_key_prefix(id:, prerequisite: nil); end

        sig { abstract.returns(String) }
        def initialization_key_prefix; end

        sig { abstract.params(type: T.nilable(Type)).void }
        def enqueue(type: nil); end

        sig { params(id: Integer, type: Type, prerequisite: T.nilable(Type)).returns(String) }
        def self.initialization_kv_key(id:, type:, prerequisite: nil)
          "#{initialization_key_prefix(id:, prerequisite:)}.#{type.serialize}"
        end

        sig { params(id: Integer, prerequisite: T.nilable(Type)).returns(T::Array[String]) }
        def self.available_metric_keys(id:, prerequisite: nil)
          Initialization::Type.all.map do |type|
            self.initialization_kv_key(id:, type:, prerequisite:)
          end
        end

        sig { abstract.returns(T::Array[Type]) }
        def self.available_initialization_types; end

        sig { abstract.returns(T.any(::Business, ::Organization, ::User)) }
        def scope; end
      end
    end
  end
end
