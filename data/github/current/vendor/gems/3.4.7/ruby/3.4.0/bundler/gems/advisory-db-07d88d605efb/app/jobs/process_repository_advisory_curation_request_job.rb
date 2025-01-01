# frozen_string_literal: true

class ProcessRepositoryAdvisoryCurationRequestJob < ApplicationJob
  queue_as :high

  def perform(repo_advisory_curation_data_hash:)
    importer = RepositoryAdvisoriesImporter.new(
      repo_advisory_curation_data: RepositoryAdvisoryCurationData.new(
        repo_advisory_curation_data_hash,
      ),
    )
    importer.import
    nil
  end
end
