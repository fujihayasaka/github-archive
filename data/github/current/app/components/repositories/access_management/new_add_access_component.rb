# typed: true
# frozen_string_literal: true

module Repositories
  module AccessManagement
    class NewAddAccessComponent < AddAccessComponent

      attr_reader :show_button_text, :title, :system_arguments

      def initialize(show_button_text:, title:, repository:, add_type:, **system_arguments)
        super(repository: repository, add_type: add_type)
        @show_button_text = show_button_text
        @title = title
        @system_arguments = system_arguments
      end

      def dialog_id
        "add-access-dialog-#{add_type}"
      end
    end
  end
end
