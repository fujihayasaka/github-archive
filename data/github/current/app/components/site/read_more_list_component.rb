# typed: true
# frozen_string_literal: true

module Site
  class ReadMoreListComponent < ApplicationComponent
    renders_many :items, Site::ReadMoreItemComponent

    def initialize(classes: nil)
      @classes = classes
    end
  end
end
