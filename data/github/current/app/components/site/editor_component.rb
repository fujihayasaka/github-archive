# typed: true
# frozen_string_literal: true

module Site
  class EditorComponent < ApplicationComponent
    def initialize(title: nil, files: [], animated: true, interactive: false, shadow_size: :medium, classes: nil, **options)
      @title = title
      @files = files
      @animated = animated
      @interactive = interactive
      @shadow_size = shadow_size
      @classes = classes
      @options = options
    end

    def filename_language(filename)
      Linguist::Language.find_by_extension(filename).first
    end

    def container_classes
      class_names(
        "color-bg-subtle rounded-3 border text-left mb-8",
        @classes,
        {
          "box-shadow-card-mktg": @shadow_size == :medium,
          "box-shadow-mktg-xl": @shadow_size == :large
        }
      )
    end

    def panel_classes
      class_names(
        "code-editor-component position-relative text-mono color-bg-default rounded-bottom-3 f4 p-3",
        {
          "js-type-in": @animated && @interactive == false,
          "code-editor-component--paused code-editor-component--interactive": @interactive
        }
      )
    end
  end
end
