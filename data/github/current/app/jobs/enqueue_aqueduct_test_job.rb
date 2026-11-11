# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnqueueAqueductTestJob < ApplicationJob
  queue_as :aqueduct_test

  schedule interval: 10.seconds, condition: -> { !GitHub.enterprise? }

  def perform
    10.times do
      AqueductTestJob.perform_later
      sleep 0.1
    end
  end
end
