# typed: true
# frozen_string_literal: true

module Dashboard
  class LoadingSpinnerComponent < ApplicationComponent

    def initialize(message = "", **system_arguments)
      @message = message
      @system_arguments = system_arguments
    end

    attr_reader :message, :system_arguments
  end
end
