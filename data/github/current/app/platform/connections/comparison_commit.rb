# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ComparisonCommit < Connections::Base
      edge_type(Objects::Commit.edge_type)

      total_count_field

      def total_count
        @object.parent.async_total_commits
      end

      field :author_count, Integer, description: "The total count of authors and co-authors across all commits.", null: false

      def author_count
        @object.parent.async_author_count
      end
    end
  end
end
