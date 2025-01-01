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

      def no_search_results_text
        entity = case add_type.to_sym
        when :user
          "GitHub account"
        when :team
          "team"
        else
          "GitHub account or team"
        end
        "No matching #{entity} found"
      end
    end
  end
end
