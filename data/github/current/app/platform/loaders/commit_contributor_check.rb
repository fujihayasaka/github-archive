# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class CommitContributorCheck < Platform::Loader
      def self.load(repository, user_id)
        self.for(repository).load(user_id)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(user_ids)
        contributor_ids = ::Collab::Responses::Array.new do
          ::ActiveRecord::Base.connected_to(role: :reading) do
            @repository.commit_contributions.
            where(user_id: user_ids).group(:user_id).pluck(:user_id)
          end
        end

        {}.tap do |result|
          user_ids.each { |id| result[id] = false }
          contributor_ids.each { |id| result[id] = true }
        end
      end
    end
  end
end
