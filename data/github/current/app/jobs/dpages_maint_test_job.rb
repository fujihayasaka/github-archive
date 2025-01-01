# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DpagesMaintTestJob < ApplicationJob

  queue_as :dpages_maint_test

  def perform
    true
  end
end
