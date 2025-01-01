# typed: true
# frozen_string_literal: true

module Sidebar
  class MemexStatusComponent < ApplicationComponent
    attr_reader :item, :status, :update_url, :readonly

    def initialize(item:, status:, update_url:, readonly:)
      @item = item
      @status = status
      @update_url = update_url
      @readonly = readonly
    end

    def render?
      !status.nil?
    end

    def current_selection
      status[:option]["id"] if status.key?(:option) && !status[:option].nil?
    end
  end
end
