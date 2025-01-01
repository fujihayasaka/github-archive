# typed: true
# frozen_string_literal: true

module UI
  class ErrorsComponent < ApplicationComponent
    attr_reader :errors, :deprecation_warnings, :mt, :mb

    # Takes a list of errors and deprecation warnings and renders them.
    #
    # errors: Array<String> (Required)
    # deprecation_warnings: Array<String> (Required)
    # mt: Integer (Optional) – the primer system arg for margin-top
    # mb: Integer (Optional) – the primer system arg for margin-bottom
    def initialize(errors, deprecation_warnings, mt: 3, mb: 0)
      @errors = errors || []
      @deprecation_warnings = deprecation_warnings || []
      @mt = mt
      @mb = mb
    end

    private

    def markdown_list(list_of_strings)
      return nil if list_of_strings.empty?
      markdown = list_of_strings.reduce(String.new) do |initial, item|
        initial << "- #{item}\n"
      end
      rich_form_message(markdown)
    end

    def rich_form_message(message)
      GitHub::Goomba::ConfigAsCodeErrorMessagePipeline.to_html(message, {})
    end
  end
end
