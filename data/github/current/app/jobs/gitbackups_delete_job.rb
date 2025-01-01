# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitbackupsDeleteJob < ApplicationJob
  queue_as :gitbackups_delete

  # don't allow multiple delete jobs for the same repo
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  # retry on all failures to communicate with gitbackupsd
  retry_on GitHub::Gitbackups::ClientError, Faraday::Error, GitBackups::DeleteError, wait: :polynomially_longer, attempts: 10

  sig { params(spec: String).void }
  def perform(spec)
    Failbot.push app: "gitbackups"

    res = GitHub::Gitbackups.client.delete spec

    raise GitBackups::DeleteError.new(res) unless res == :ok || res == :not_found
  end
end
