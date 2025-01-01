# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class NotificationsSummaries < ApplicationRecord::NotificationsSummaries
      self.abstract_class = true
    end
  end
end
