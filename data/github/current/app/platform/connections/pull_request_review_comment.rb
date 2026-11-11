# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PullRequestReviewComment < Connections::Base
      description "The connection type for PullRequestReviewComment."

      total_count_field

      field :filtered_count, Integer, visibility: :internal, description: "Identifies the count of items after applying `before` and `after` filters.", null: false

      field :page_count, Integer, visibility: :internal, description: "Identifies the count of items after applying `before`/`after` filters and `first`/`last`/`skip` slicing.", null: false

      field :before_focus_count, Integer, visibility: :internal, description: "Identifies the count of items before the focused item (`focus`).", null: false

      field :after_focus_count, Integer, visibility: :internal, description: "Identifies the count of items after the focused item (`focus`).", null: false
    end
  end
end
