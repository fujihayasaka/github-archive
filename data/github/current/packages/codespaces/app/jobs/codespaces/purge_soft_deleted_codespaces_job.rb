# typed: true
# frozen_string_literal: true

class Codespaces::PurgeSoftDeletedCodespacesJob < CodespacesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  schedule interval: 30.minutes, condition: -> { !GitHub.enterprise? }

  def perform
    Codespace.purgable.find_each do |codespace|
      with_write do
        Codespace.throttle_with_retry { codespace.destroy }
      end
      GitHub.dogstats.increment("codespaces_purged.count")
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e, "gh.codespaces.id" => codespace.id)
      next
    end
  end
end
