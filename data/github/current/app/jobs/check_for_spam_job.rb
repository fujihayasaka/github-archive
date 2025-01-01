# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CheckForSpamJob < ApplicationJob
  class NoAdminsWhileCheckingForSpamError < StandardError; end

  queue_as :spam

  retry_on_dirty_exit

  retry_on NoAdminsWhileCheckingForSpamError

  def perform(record_klass, record_id, options = {})
    return unless record = record_klass.constantize.find_by_id(record_id)

    GitHub.dogstats.time "spam.jobs.check_for_spam", tags: ["class:#{record_klass.to_s.parameterize}"] do
      begin
        original_component = GitHub.component
        GitHub.component = "resque_check_for_spam_#{record_klass.underscore}".to_sym

        raise NoAdminsWhileCheckingForSpamError if record.is_a?(Organization) && record.admins.empty?
        record.check_for_spam(options.symbolize_keys)
      ensure
        GitHub.component = original_component
      end
    end
  end

  def self.enqueue(record, options = {})
    return unless GitHub.spamminess_check_enabled?
    return if record.respond_to?(:exempt_from_spam_check_after_signup?) && record.exempt_from_spam_check_after_signup?

    CheckForSpamJob.perform_later(record.class.name, record.id, options)
  end
end
