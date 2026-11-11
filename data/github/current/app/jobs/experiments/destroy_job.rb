# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Experiments
  class DestroyJob < ApplicationJob
    queue_as :science_event_cleanup

    discard_on ActiveJob::DeserializationError
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(experiment)
      with_write { experiment.destroy }
    end
  end
end
