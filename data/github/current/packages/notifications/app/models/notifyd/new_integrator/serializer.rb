# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  class Serializer
    extend T::Sig

    sig { params(value: T.untyped).returns(T.untyped) }
    def self.serialize(value)
      new.serialize(value)
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    def serialize(value)
      case value
      when Hash
        serialize_hash(value)
      when Array
        serialize_array(value)
      when Serializable
        serialize_serializable(value)
      else
        value
      end
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def serialize_hash(hash)
      hash.reduce({}) do |acc, (key, value)|
        acc[key] = serialize(value)
        acc
      end
    end

    sig { params(array: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def serialize_array(array)
      array.reduce([]) do |acc, value|
        acc.push(serialize(value))
        acc
      end
    end

    sig { params(serializable: Serializable).returns(T.untyped) }
    def serialize_serializable(serializable)
      serialize(serializable.as_serializable)
    end
  end
end
