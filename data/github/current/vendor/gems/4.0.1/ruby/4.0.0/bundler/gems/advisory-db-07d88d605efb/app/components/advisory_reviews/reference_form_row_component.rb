# frozen_string_literal: true

module AdvisoryReviews
  class ReferenceFormRowComponent < ApplicationComponent
    attr_reader :name, :reference

    delegate :url,
      to: :reference,
      allow_nil: true

    def initialize(name:, reference: nil, disabled: false)
      @name = name
      @reference = reference
      @disabled = disabled
    end

    def visible?
      !reference.nil?
    end
  end
end
