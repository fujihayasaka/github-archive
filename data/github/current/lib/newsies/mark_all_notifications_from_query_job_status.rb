# typed: true
# frozen_string_literal: true

module Newsies
  class MarkAllNotificationsFromQueryJobStatus
    JOB_KEY = "mark-all-notifications-from-query"

    def self.job_id(user_id)
      "#{JOB_KEY}-#{user_id}"
    end

    def self.create(id:, ttl:)
      JobStatus.create(id: self.job_id(id), ttl: ttl)
    end

    def self.existing_job_running?(user_id)
      status = self.status(user_id)
      return false unless status

      !status.finished?
    end

    def self.status(user_id)
      JobStatus.find(self.job_id(user_id))
    end
  end
end
