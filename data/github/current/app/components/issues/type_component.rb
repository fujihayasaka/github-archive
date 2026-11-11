# typed: true
# frozen_string_literal: true

module Issues
  class TypeComponent < ApplicationComponent
    COLOR_SCHEME_MAP = {
      "gray" => {
        bg: "muted",
        border: "muted",
        fg: "muted",
      },
      "blue" => {
        bg: "accent-muted",
        border: "accent-muted",
        fg: "accent",
      },
      "green" => {
        bg: "success-muted",
        border: "success-muted",
        fg: "success",
      },
      "yellow" => {
        bg: "attention-muted",
        border: "attention-muted",
        fg: "attention",
      },
      "orange" => {
        bg: "severe-muted",
        border: "severe-muted",
        fg: "severe",
      },
      "red" => {
        bg: "danger-muted",
        border: "danger-muted",
        fg: "danger",
      },
      "pink" => {
        bg: "sponsors-muted",
        border: "sponsors-muted",
        fg: "sponsors",
      },
      "purple" => {
        bg: "done-muted",
        border: "done-muted",
        fg: "done",
      },
    }.freeze

    def initialize(issue_type:, **system_arguments)
      @issue_type = issue_type
      @system_arguments = system_arguments

      if @issue_type.present?
        @system_arguments[:tag] = :span
        @system_arguments[:style] = style
        @system_arguments[:classes] = class_names(
          "d-inline-flex",
          "flex-items-center",
          "v-align-text-top",
          @system_arguments[:classes]
        )
      end
    end

    private

    def render?
      @issue_type.present?
    end

    def color_scheme
      color = @issue_type.color.to_s.downcase
      COLOR_SCHEME_MAP.fetch(color, COLOR_SCHEME_MAP["gray"])
    end

    def style
      scheme = color_scheme
      [
        "background-color: var(--bgColor-#{scheme[:bg]}, var(--color-canvas-subtle));",
        "border: var(--borderWidth-thin) solid var(--borderColor-#{scheme[:border]});",
        "color: var(--fgColor-#{scheme[:fg]}, var(--color-fg-muted));",
        "border-radius: var(--borderRadius-full);",
        "font-weight: var(--base-text-weight-semibold);",
        "font-size: var(--text-body-size-small, .75rem);",
        "padding: 0 var(--base-size-8, 8px);",
      ].join(" ")
    end
  end
end
