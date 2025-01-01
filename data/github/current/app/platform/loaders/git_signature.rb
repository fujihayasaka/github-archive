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
        # the repo variable can be removed when both the :process_authentic_commits and :save_lazy_authentic_commits
        # FFs are removed. it is only used to check if an FF is enabled, so it's okay if the commits here are somehow
        # from multiple different repos.
        repo = objects.first.repository if objects&.first
        @klass.prefill_verified_signature(objects, repo)

        objects.map do |object|
          [object, object.has_signature? ? object.signature_object : nil]
        end.to_h
      end
    end
  end
end
