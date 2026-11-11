# typed: true
# frozen_string_literal: true

class CodeScanning::PrettyCronComponent < ApplicationComponent
  def initialize(cron:)
    @cron = cron
  end
end
