# frozen_string_literal: true

class RepositoryAdvisoriesImporter < ApplicationImporter
  # this is used only from the hydro processor
  disable_auto_import

  attr_reader :repo_advisory_curation_data

  def initialize(repo_advisory_curation_data:)
    @repo_advisory_curation_data = repo_advisory_curation_data
  end

  def each(&)
    [repo_advisory_curation_data.importer_object].each(&)
  end
end
