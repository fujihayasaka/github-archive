# typed: true
# frozen_string_literal: true

module HelpHub
  class CriticalMailersDeliveryJob < ApplicationDeliveryJob
    queue_as :helphub_critical_mailers
  end
end
