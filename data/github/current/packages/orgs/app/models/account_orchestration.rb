# typed: strict
# frozen_string_literal: true

module AccountOrchestration
  extend T::Helpers
  extend ActiveSupport::Concern

  module ClassMethods
    sig { params(values: T::Array[Integer]).returns(String) }
    def encode(values)
      values.map(&:to_i).map { |i| [i].pack("Q<") }.join("")
    end

    sig { params(values: String).returns(T::Array[Integer]) }
    def decode(values)
      values.unpack("Q<*").map(&:to_i).compact
    end
  end

  mixes_in_class_methods(ClassMethods)
end
