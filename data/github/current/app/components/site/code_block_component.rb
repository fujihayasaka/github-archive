# typed: true
# frozen_string_literal: true

module Site
  class CodeBlockComponent < ApplicationComponent
    include SvgHelper

    DEFAULT_TYPE = :marketing_copilot
    TYPES = T.let([:marketing_copilot, :pull_request_popover].freeze, T::Array[Symbol])

    attr_reader :type

    def initialize(file:, classes: nil, animated: true, interactive: false, hide_replay: false, font_size: 4, type: DEFAULT_TYPE, **options)
      @file = file
      @classes = classes
      @animated = animated
      @interactive = interactive
      @hide_replay = hide_replay
      @font_size = font_size
      @options = options
      @type = T.let(fetch_or_fallback(TYPES, type, DEFAULT_TYPE), Symbol)
    end

    def filename_language(filename)
      Linguist::Language.find_by_extension(filename).first
    end

    def syntax_highlight(filename, code)
      code_digest = Digest::SHA256.hexdigest(code)
      cache_key = "site_code_block_component_#{code_digest}"

      GitHub.cache.fetch(cache_key) do
        scope = filename_language(filename).try(:tm_scope)
        GitHub::Colorize.highlight_one(scope, code)
      end
    end

    def container_classes
      class_names(
        @classes
      )
    end

    def font_size
      "f#{@font_size}"
    end

    def show_replay_button?
      return false if @hide_replay
      return false unless @animated
      return false unless has_suggestions(@file)
      return false if @interactive

      true
    end

    memoize def avoid_scss_bundle?
      @type == :pull_request_popover
    end

    def line_params(line_number, file)
      suggested_line = @file[:suggested_line_start].present? && line_number >= @file[:suggested_line_start]
      animated_line = @animated && line_number >= (@file[:animated_line_start] || 0)

      inline_style = "padding-left: 6px !important;"
      inline_style = "#{inline_style} border-left: 2px solid;" if suggested_line

      {
        class: class_names(
          "code-editor-line-mktg d-inline-block",
          {
            "js-type-letters": animated_line && !suggested_line,
            "js-type-row": animated_line && suggested_line,
            "code-editor-line-suggested-mktg color-bg-accent": suggested_line && !avoid_scss_bundle?,
            "code-editor-line-suggested-mktg color-bg-accent color-border-accent-emphasis": suggested_line && avoid_scss_bundle?,
          }
        ),
        data: {
          "type-row-delay": suggested_line ? 0 : nil
        },
        style: avoid_scss_bundle? ? inline_style : nil
      }
    end

    def suggestion_classes
      class_names(
        "copilot-marker position-absolute color-fg-on-emphasis rounded color-bg-accent-emphasis text-bold d-flex flex-items-center js-type-row",
        {
          "p-2 f5": !avoid_scss_bundle?,
          "f6": avoid_scss_bundle?,
        }
      )
    end

    def suggestion_styles
      return "" if !avoid_scss_bundle?
      "padding: 6px 11px !important; border-top-left-radius: 0 !important;"
    end

    def line_number_styles
      return "" if !avoid_scss_bundle?
      "padding-right: 6px;"
    end

    def has_suggestions(file)
      file[:suggested_line_start].present?
    end
  end
end
