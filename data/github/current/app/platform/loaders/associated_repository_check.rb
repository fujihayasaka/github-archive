# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class AssociatedRepositoryCheck < Platform::Loader
      def self.load(user, repository_id, **options)
        self.for(user, **options).load(repository_id)
      end

      def initialize(user, **options)
        @user = user
        @options = options
      end

      def fetch(repository_ids)
        result = user.associated_repository_ids(repository_ids: repository_ids, **options).map { |id| [id, true] }.to_h
        result.default = false
        result
      end

      private

      attr_reader :user
      attr_reader :options
    end
  end
end
