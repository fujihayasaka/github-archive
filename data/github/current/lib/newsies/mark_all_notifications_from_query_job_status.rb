# typed: true
# frozen_string_literal: true

module Newsies
  class MarkAllNotificationsFromQueryJobStatus
    JOB_KEY = "mark-all-notifications-from-query"

    def self.job_id(user_id)
      "#{prefix}-#{user_id}"
    end

    def self.prefix
      JOB_KEY
    end

    def self.create(id:, ttl:)
      Notifications::JobStatus.create(id: self.job_id(id), ttl: ttl)
    end

    def self.existing_job_running?(user_id)
      status = self.status(user_id)
      return false unless status

      !status.finished?
    end

    def self.status(user_id)
      Notifications::JobStatus.find(self.job_id(user_id))
    end
  end
end
