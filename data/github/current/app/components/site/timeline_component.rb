# typed: true
# frozen_string_literal: true

module Site
  class TimelineComponent < ApplicationComponent
    VERSION = "1.0.0"

    renders_many :items

    def initialize(classes: nil, item_classes: nil)
      @classes = classes
      @item_classes = item_classes
    end

    def list_classes
      class_names(
        "list-style-none f3-mktg color-fg-muted col-sm-10 pl-2 mb-n4 mb-md-n6",
        @classes,
      )
    end

    def item_classes
      class_names(
        "timeline-list-item-mktg pb-4 pb-md-6 pl-4 js-build-in-item build-in-scale-up",
        @item_classes,
      )
    end
  end
end
