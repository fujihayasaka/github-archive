# typed: true
# frozen_string_literal: true

module Pages
  class VisibilityComponent < ApplicationComponent
    include SvgHelper
    include PagesHelper

    attr_reader :repository

    def initialize(repository:)
      @repository = repository
    end

    def page
      @repository.page
    end

    memoize def pages_build_types?
      return false unless page
      page.build_types_enabled?
    end

    def archived?
      @repository.archived?
    end

    # padding bottom css style
    def pb
      "pb-5" unless pages_build_types?
    end
  end
end
