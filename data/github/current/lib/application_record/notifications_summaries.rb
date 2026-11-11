# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class NotificationsSummaries < Base
    self.abstract_class = true

    connects_to database: { writing: :notifications_summaries_primary, reading: :notifications_summaries_readonly }

    def self.throttler_cluster_name
      # This is the actual name set to the cluster, it doesn't match the name of the class
      :"notification-summaries"
    end
  end
end
