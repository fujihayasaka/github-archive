# typed: true
# frozen_string_literal: true
#
module Hooks
  class DeliveriesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :deliveries, :outages, :current_hook, :use_new_hooks_ui, :next_cursor, :status, :error

    def take_outages_after(time)
      outages_after_time = outages.take_while do |outage|
        Time.parse(outage["from"]) > time
      end
      outages.shift(outages_after_time.length)
      outages_after_time
    end
  end
end
