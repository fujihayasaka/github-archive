# frozen_string_literal: true

module CVEReviewTriage
  class AffectedProductRowComponent < ApplicationComponent
    attr_reader :ecosystem, :package

    def initialize(ecosystem:, package:)
      @ecosystem = ecosystem
      @package = package
    end
  end
end
