# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PullRequestOrder < Platform::Inputs::Base
      description "Ways in which lists of issues can be ordered upon return."

      argument :field, Enums::PullRequestOrderField, "The field in which to order pull requests by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order pull requests by the specified field.", required: true
    end
  end
end
