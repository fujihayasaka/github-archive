# typed: true
# frozen_string_literal: true

module Codespaces
  class FindAffectedCodespacesByOrganization < Command
    attr_reader :deletion_reason

    def initialize(organization_id:, disabled: false, deletion_reason: nil)
      @organization_id = organization_id
      @disabled = disabled
      @deletion_reason = deletion_reason
    end

    def perform
      organization = Organization.find(@organization_id)

      if @disabled
        process_disabled_codespaces(organization)
      else
        process_enabled_codespaces(organization)
      end
    end

    private

    # when the admin disables codespaces, we need to go through all of the codespaces
    # where the organization is the billable_owner and check the ownership
    def process_disabled_codespaces(organization)
      Codespace.for_organization(organization).in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.to_a, deletion_reason: deletion_reason)
      end
    end

    # when the admin enables codespaces, we need to go through all of the repositories and
    # check ownership on all of the codespaces. some organizations have > 30k repositories
    # so we want to do this in batches of batches
    # tl;dr it's batches all the way down
    def process_enabled_codespaces(organization)
      organization.repositories.in_batches do |repository_batch|
        repository_ids = repository_batch.pluck(:id).uniq
        Codespace.where(repository: repository_ids).in_batches do |codespace_batch|
          CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.to_a, deletion_reason: deletion_reason)
        end
      end
    end
  end
end
