# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TeamDiscussionByNumber < Platform::Loader
      def self.load(team_id, number)
        self.for(team_id).load(number)
      end

      def self.load_all(team_id, numbers)
        loader = self.for(team_id)
        Promise.all(numbers.map { |number| loader.load(number) })
      end

      def initialize(team_id)
        @team_id = team_id
      end

      def fetch(numbers)
        ::DiscussionPost.where(team_id: @team_id, number: numbers).index_by(&:number)
      end
    end
  end
end
