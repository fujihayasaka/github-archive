# typed: true
# frozen_string_literal: true

class Codespaces::CheckForShutdownCodespacesJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 60.minutes, condition: -> { !GitHub.enterprise? }

  BATCH_SIZE = 100

  retry_on_dirty_exit

  def perform
    # We use Codespaces::MAX_SESSION_TIME * 4 here so we can feel quite confident the user isn't
    # in the middle of a codespaces session
    codespaces = if GitHub.flipper[:codespaces_clean_up_stuck_provisioning].enabled?
      Codespace.provisioned.where(shutdown_at: nil).where("last_used_at < ?", (Codespaces::MAX_SESSION_TIME * 4).ago).limit(1000)
    else
      Codespace.where(shutdown_at: nil).where("last_used_at < ?", (Codespaces::MAX_SESSION_TIME * 4).ago).limit(1000)
    end

    updated = 0
    now = Time.now
    with_write do
      codespaces.find_each do |codespace|
        # An exporting codespace goes through states that are using compute and thus blank out `shutdown_at` BUT
        # they don't modify the codespace's `last_used_at` value. That can make them show up in this list
        next if codespace.exporting? && GitHub.flipper[:codespaces_clean_up_stuck_provisioning].enabled?

        if codespace.vscs_target&.to_sym == :production
          # Only log/emit metrics for production codespaces
          GitHub.logger.info(
            "Codespaces::CheckForShutdownCodespacesJob found codespace to shutdown",
            "gh.catalog_service" => "github/codespaces",
            "gh.codespaces.guid" => codespace.guid,
            "gh.codespaces.environment_state" => codespace.environment_data&.state,
            "gh.codespaces.last_used_at" =>  codespace.last_used_at,
          )
          updated += 1
        end

        codespace.update!(shutdown_at: now)
      rescue ActiveRecord::RecordInvalid => e
        codespace.update_attribute(:shutdown_at, now)
      end
    end

    GitHub.dogstats.count("codespaces.check_for_shutdown_codespaces.updated", updated)
  end
end
