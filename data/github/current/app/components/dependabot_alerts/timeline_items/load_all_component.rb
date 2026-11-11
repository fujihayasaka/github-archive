# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class LoadAllComponent < ApplicationComponent

    attr_reader :load_all_path, :hidden_items_count

    def initialize(load_all_path:, hidden_items_count:)
      @load_all_path = load_all_path
      @hidden_items_count = hidden_items_count
    end
  end
end
