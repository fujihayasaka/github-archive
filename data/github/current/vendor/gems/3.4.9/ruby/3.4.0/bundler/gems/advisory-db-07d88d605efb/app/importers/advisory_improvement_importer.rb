# frozen_string_literal: true

class AdvisoryImprovementImporter < ApplicationImporter
  # this is used only from the hydro and webhook processors
  disable_auto_import

  attr_reader :advisory_improvement_data

  def initialize(advisory_improvement_data:)
    @advisory_improvement_data = advisory_improvement_data
  end

  def each(&)
    [advisory_improvement_data.importer_object].each(&)
  end
end
