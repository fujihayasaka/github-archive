# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueishByNumber < Platform::Loader
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
        pulls_by_number = PullRequestByNumber.new(@repository_id).fetch(numbers)
        remaining_numbers = numbers - pulls_by_number.keys
        issues_by_number = IssueByNumber.new(@repository_id).fetch(remaining_numbers)
        pulls_by_number.merge(issues_by_number)
      end
    end
  end
end
