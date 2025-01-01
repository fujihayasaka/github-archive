# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DisableGistAccessJob < ApplicationJob
  class GistDisableError < StandardError; end

  queue_as :gist_access

  discard_on ActiveJob::DeserializationError do |_job, error|
    Failbot.report(error)
  end

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  before_enqueue do |job|
    gist = job.arguments[0]
  end

  def perform(gist, reason, user, **opts)
    with_write do
      result = gist.access.disable(reason, user, **opts)

      # Make job fail if we failed to disable one or more gists in network
      failed = !result || (result.is_a?(Hash) && result[:failures].any?)
      raise GistDisableError.new("Failed to disable gist: #{gist.id}") if failed
    end
  end
end
