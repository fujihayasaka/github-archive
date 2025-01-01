# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class NotificationsDeliveries < ApplicationRecord::NotificationsDeliveries
      include ApplicationRecord::UTCRecord

      self.abstract_class = true
    end
  end
end
