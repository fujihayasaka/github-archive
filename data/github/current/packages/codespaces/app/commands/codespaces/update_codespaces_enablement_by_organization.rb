
# typed: true
# frozen_string_literal: true
# Similar to FindAffectedCodespacesByOrganization

module Codespaces
  class UpdateCodespacesEnablementByOrganization < Command

    def initialize(organization_id:, disabled: false)
      @organization_id = organization_id
      @disabled = disabled #currently behavior is the same regardless of this value
    end

    def perform
      organization = Organization.find(@organization_id)

      queue_system_event_job_for_org_repositories(organization)
    end

    private

    # when the admin enables/disable codespaces, we need to go through all of the repositories and
    # check ownership on all of the codespaces.  some organizations have > 30k repositories
    # so we want to do this in batches of batches
    # tl;dr it's batches all the way down
    def queue_system_event_job_for_org_repositories(organization)
      organization.repositories.in_batches do |repository_batch|
        repository_ids = repository_batch.pluck(:id).uniq
        Codespace.where(repository: repository_ids).in_batches do |codespace_batch|
          CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.sort)
        end
      end
    end
  end
end
