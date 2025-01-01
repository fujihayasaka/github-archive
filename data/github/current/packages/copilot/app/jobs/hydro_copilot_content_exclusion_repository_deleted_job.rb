# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/deleted_pb"

class HydroCopilotContentExclusionRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_copilot_content_exclusion_repository_deleted

  retry_on_dirty_exit

  sig { void }
  def perform
    GitHub.logger.with_named_tags("code.namespace": self.class.name, "code.function": __method__) do
      GitHub.dogstats.distribution_time("copilot.content_exclusion.repository_delete_job.duration") do
        deleted_entities = with_write do
          Copilot::ContentExclusionConfiguration.for_repository_ids([payload.repository_id]).destroy_all
        end

        count = deleted_entities.count

        GitHub.dogstats.histogram("copilot.content_exclusion.destroy_rules", count)
        GitHub.logger.info("Purged content exclusion repo level configuration", {
          "gh.copilot.ignore.deleted.count": count
        }) if count > 0
      end
    end
  end

  protected

  sig { returns(::Hydro::Schemas::Github::Repositories::V1::Deleted) }
  memoize def payload
    ::Hydro::Schemas::Github::Repositories::V1::Deleted.new(message)
  end
end
