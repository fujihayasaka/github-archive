# typed: true
# frozen_string_literal: true

module Site
  class HstackComponent < ApplicationComponent
    def initialize(classes: nil, animate: true, stagger: nil)
      @classes = classes
      @animate = animate
      @stagger = stagger.present? ? "data-build-in-stagger=#{stagger}" : nil
    end

    def container_classes
      class_names(
        "d-flex flex-column flex-md-row gutter",
        {
          "js-build-in-trigger": @animate == true
        }
      )
    end
  end
end
