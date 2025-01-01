# typed: true
# frozen_string_literal: true

module SlashCommands
  class ErrorMessageComponent < ApplicationComponent
    attr_reader :title, :message

    def initialize(message:, title: "An error has occurred")
      @message = message
      @title = title
    end

    private

    def rich_message
      GitHub::Goomba::ConfigAsCodeErrorMessagePipeline.to_html(message, {})
    end
  end
end
