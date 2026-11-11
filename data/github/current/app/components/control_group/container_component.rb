# typed: strict
# frozen_string_literal: true

module ControlGroup
  class ContainerComponent < ApplicationComponent
    renders_one :header

    sig { params(test_selector: T.nilable(String), classes: T.nilable(String)).void }
    def initialize(test_selector: nil, classes: nil)
      @test_selector = test_selector
      @classes = classes
    end

    private

    sig { returns(String) }
    def container_classes
      class_names(
        "ControlGroup",
        @classes,
      )
    end
  end
end
