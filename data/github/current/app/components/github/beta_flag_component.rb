# typed: true
# frozen_string_literal: true

module GitHub
  class BetaFlagComponent < ApplicationComponent
    attr_reader :label

    def initialize(label: "Beta", **kwargs)
      @label = label
      @kwargs = kwargs
      @kwargs[:variant] ||= :inline
      @kwargs[:scheme] = :success
    end

    def call
      render(Primer::Beta::Label.new(**@kwargs)) { label }
    end
  end
end
