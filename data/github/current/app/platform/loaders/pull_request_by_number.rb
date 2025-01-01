# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestByNumber < Platform::Loader
      def self.load(repository_id, number)
        self.for(repository_id).load(number)
      end

      def self.load_all(repository_id, numbers)
        loader = self.for(repository_id)
        Promise.all(numbers.map { |number| loader.load(number) })
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(numbers)
        ::PullRequest.includes(:issue).joins(:issue)
          .readonly(false)
          .where(issues: { repository_id: @repository_id, number: numbers })
          .index_by(&:number)
      end
    end
  end
end
