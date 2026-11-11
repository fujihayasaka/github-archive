# frozen_string_literal: true

class ProcessImproveAdvisoryRequestJob < ApplicationJob
  queue_as :high

  def perform(advisory_improvement_data_hash:)
    importer = AdvisoryImprovementImporter.new(
      advisory_improvement_data: AdvisoryImprovementData.new(
        advisory_improvement_data_hash,
      ),
    )
    importer.import
  end
end
