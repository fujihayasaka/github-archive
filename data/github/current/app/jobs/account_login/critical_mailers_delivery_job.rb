# typed: true
# frozen_string_literal: true

module AccountLogin
  class CriticalMailersDeliveryJob < ApplicationDeliveryJob
    queue_as :account_login_critical_mailers
  end
end
