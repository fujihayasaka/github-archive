# frozen_string_literal: true

class ImportJob < ApplicationJob
  queue_as :high

  retry_on NVDImporter::NVDUnavailableError, queue: :high, wait: :polynomially_longer
  retry_on Net::ReadTimeout, queue: :high, wait: :polynomially_longer, attempts: 2

  def perform(source, **args)
    ApplicationImporter.importer_for_source(source).import(**args)
  end
end
