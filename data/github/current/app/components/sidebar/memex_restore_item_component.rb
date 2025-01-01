# typed: true
# frozen_string_literal: true

module Sidebar
  class MemexRestoreItemComponent < ApplicationComponent
    attr_reader :item, :unarchive_url, :readonly

    def initialize(item:, unarchive_url:, readonly:)
      @item = item
      @unarchive_url = unarchive_url
      @readonly = readonly
    end
  end
end
