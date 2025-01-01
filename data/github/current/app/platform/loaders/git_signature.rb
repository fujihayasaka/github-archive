# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class GitSignature < Platform::Loader
      def self.load(object)
        self.for(object.class).load(object)
      end

      def initialize(klass)
        @klass = klass
      end

      def fetch(objects)
        @klass.prefill_verified_signature(objects)
        objects.map do |object|
          [object, object.has_signature? ? object.signature_object : nil]
        end.to_h
      end
    end
  end
end
