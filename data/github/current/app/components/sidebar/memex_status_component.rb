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

    # Returns sanitized display HTML for a status option, re-rendered from the clean "name" field.
    def display_name_html(option)
      GitHub::Goomba::MemexTextColumnPipeline.to_html(option["name"] || "")
    end
  end
end
