# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/transferred_pb"

class HydroCopilotContentExclusionRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_copilot_content_exclusion_repository_transferred

  retry_on_dirty_exit

  sig { void }
  def perform
    GitHub.logger.with_named_tags("code.namespace": self.class.name, "code.function": __method__) do
      GitHub.dogstats.distribution_time("copilot.content_exclusion.repository_transferred_job.duration") do
        new_owner_id = T.must(payload.new_owner).id
        previous_owner_id = T.must(payload.previous_owner).id

        count = with_write do Copilot::ContentExclusionConfiguration.with_organization_ids(previous_owner_id)
          .where(resource_type: "Repository")
          .update_all(organization_id: new_owner_id)
        end

        GitHub.logger.info("Organization relationships updated for transferred repositories", {
          "gh.copilot.ignore.updated.count": count
        }) if count > 0
      end
    end
  end

  protected

  sig { override.returns(T::Hash[String, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
  def logging_context
    super.merge({
      "gh.repo.previous_owner.id": T.must(payload.previous_owner).id,
      "gh.repo.new_owner.id": T.must(payload.new_owner).id,
    })
  end

  sig { returns(::Hydro::Schemas::Github::Repositories::V1::Transferred) }
  memoize def payload
    ::Hydro::Schemas::Github::Repositories::V1::Transferred.new(message)
  end
end
