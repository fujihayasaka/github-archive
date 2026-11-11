# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class DeletedActorsFilter < BaseFilter
    def self.apply(events, viewer)
      events.delete_if { |event| event.sender_record.blank? }
    end
  end
end
