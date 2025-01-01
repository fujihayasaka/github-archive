# typed: true
# frozen_string_literal: true

module GitHub
  class DialogComponent < ApplicationComponent
    renders_one :summary
    renders_one :header
    renders_one :alert
    renders_one :footer
    renders_one :body

    VARIANTS = {
      default: "Box--overlay",
      narrow: "Box-overlay--narrow",
      wide: "Box-overlay--wide",
    }.freeze

    def initialize(
        title:,
        id: nil,
        src: nil,
        preload: false,
        variant: :default,
        details_classes: nil,
        dialog_classes: nil,
        onclose: nil,
        header_classes: nil,
        title_classes: nil,
        body_classes: nil,
        body_overflow_auto: true,
        aria_described_by: nil
      )
      @title = title
      @id = id
      @src = src
      @preload = preload
      @variant_classes = VARIANTS.fetch(variant, :default)
      @details_classes = details_classes
      @dialog_classes = class_names(dialog_classes)
      @onclose = onclose
      @header_classes = class_names("Box-header", header_classes)
      @title_classes = class_names("Box-title", title_classes)
      @body_classes = class_names(
        "Box-body",
        body_classes,
        "overflow-auto" => body_overflow_auto,
      )
      @aria_described_by = aria_described_by
    end

    private

    attr_reader :title, :id, :src, :preload
  end
end
