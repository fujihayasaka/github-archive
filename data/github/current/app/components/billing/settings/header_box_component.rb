# typed: true
# frozen_string_literal: true

module Billing::Settings
  class HeaderBoxComponent < ApplicationComponent
    attr_reader :title, :error, :amount, :context

    def initialize(title:, error: nil, amount: nil, context: nil)
      @title = title
      @error = error
      @amount = amount
      @context = context
    end

    renders_one :subtitle
    renders_one :additional_content
  end
end
