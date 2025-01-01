# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class CheckRunItemComponent < ApplicationComponent
      attr_reader :check_run, :os_icon

      include SvgHelper

      def initialize(check_run:, os_icon: nil)
        @check_run = check_run
        @os_icon = os_icon
      end

    end
  end
end
