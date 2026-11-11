# typed: true
# frozen_string_literal: true

module ConfigAsCode
  class EditorSidebarComponent < ApplicationComponent
    attr_reader :markdown_content
    renders_one :body

    def initialize(markdown_content)
      @markdown_content = markdown_content
    end
  end
end
