# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class NotificationsEntries < ApplicationRecord::NotificationsEntries
      include ApplicationRecord::UTCRecord

      self.abstract_class = true
    end
  end
end
