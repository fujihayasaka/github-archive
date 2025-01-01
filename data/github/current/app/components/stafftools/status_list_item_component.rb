# typed: true
# frozen_string_literal: true

module Stafftools
  class StatusListItemComponent < ApplicationComponent
    STATUSES = %i(error success neutral).freeze
    DEFAULT_STATUS = :neutral

    # status - Symbol indicating the sentiment of this list item; choose from :error, :success, :neutral
    # message - String of text to explain the status
    # system_arguments - optional Hash; see https://primer.style/view-components/system-arguments
    def initialize(message:, tag: :li, status: DEFAULT_STATUS, **system_arguments)
      @message = message
      @tag = tag
      @status = fetch_or_fallback(STATUSES, status, DEFAULT_STATUS)
      @system_arguments = system_arguments
      @system_arguments[:classes] = class_names(
        @system_arguments[:classes],
        "failed" => @status == :error,
        "neutral" => @status == :neutral,
      )
    end

    private

    attr_reader :message, :status, :system_arguments, :tag

    def render?
      message.present?
    end

    def icon
      case status
      when :error then :alert
      when :success then :check
      when :neutral then :info
      else :x
      end
    end

    def icon_color
      case status
      when :error then :danger
      when :success then :success
      else :accent
      end
    end
  end
end
