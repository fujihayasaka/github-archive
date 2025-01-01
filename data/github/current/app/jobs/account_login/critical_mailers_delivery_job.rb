# typed: true
# frozen_string_literal: true

module AccountLogin
  class CriticalMailersDeliveryJob < ApplicationDeliveryJob
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    queue_as :account_login_critical_mailers
  end
end
