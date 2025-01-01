# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class WorkflowJobNameLinkComponent < ApplicationComponent
      attr_reader :url, :name

      def initialize(name:, url:, show_tooltip: false)
        @name = name
        @url = url
        @show_tooltip = show_tooltip
      end

      def truncated_name
        return nil if @name.blank?
        @truncated_name ||= @name.gsub(/ \/ .* \/ /, " / ... / ")
      end

      def show_tooltip?
        @show_tooltip && (truncated_name != name)
      end

      memoize def id
        SecureRandom.alphanumeric(5)
      end
    end
  end
end
