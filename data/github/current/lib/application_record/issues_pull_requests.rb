# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class IssuesPullRequests < Base
    include GitHub::MaxExecutionTime

    self.abstract_class = true

    def self.cluster_name
      :"issues-pull-requests"
    end

    def self.dedicated_background_destroy_queue_name
      "background_destroy_#{cluster_name.to_s.underscore}".to_sym
    end

    connects_to database: {
      writing: :issues_pull_requests_primary,
      reading: :issues_pull_requests_readonly,
      reading_slow: :issues_pull_requests_readonly_slow
    }
  end
end
