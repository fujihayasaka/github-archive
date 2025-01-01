# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module PullRequestStatusFilter
      def self.filter(scope, states)
        case states.sort
        when %w[closed]
          scope.where(merged_at: nil, status: "closed")
        when %w[closed merged]
          scope.where("merged_at IS NOT NULL OR status = ?", "closed")
        when %w[closed open]
          scope.where(merged_at: nil)
        when %w[merged]
          scope.where("merged_at IS NOT NULL")
        when %w[merged open]
          scope.where("merged_at IS NOT NULL OR status = ?", "open")
        when %w[open]
          scope.where(status: "open")
        else
          scope
        end
      end
    end
  end
end
