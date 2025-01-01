# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class NotificationsDeliveries < Base
    self.abstract_class = true

    connects_to database: { writing: :notifications_deliveries_primary, reading: :notifications_deliveries_readonly }
  end
end
