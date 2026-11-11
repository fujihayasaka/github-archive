# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class NotificationsEntries < Base
    include GitHub::MaxExecutionTime

    self.abstract_class = true

    connects_to database: { writing: :notifications_entries_primary, reading: :notifications_entries_readonly }
  end
end
