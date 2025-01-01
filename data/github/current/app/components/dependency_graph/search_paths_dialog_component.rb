# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SearchPathsDialogComponent < ApplicationComponent
    delegate :package_name,
      to: :@search_result
    attr_reader :dialog_id, :search_result

    def initialize(search_result:, dialog_id:)
      @search_result = search_result
      @dialog_id = dialog_id
    end

    def title_text
      escaped_package_name = ERB::Util.html_escape(package_name)
      escaped_requirements = ERB::Util.html_escape(requirements)

      "Paths for #{escaped_package_name} #{escaped_requirements}"
    end

    def root_ancestors
      @search_result.root_ancestors.to_a
    end

    def requirements
      @search_result.requirements
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end

    def is_direct_and_transitive?
      @search_result.relationship == :RELATIONSHIP_DIRECT && root_ancestors.length > 0
    end
  end
end
