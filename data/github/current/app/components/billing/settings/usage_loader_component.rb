# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class UsageLoaderComponent < ApplicationComponent
      renders_one :placeholder

      attr_reader :loading_text, :source, :classes, :test_selector

      def initialize(loading_text: nil, source:, classes: nil, test_selector: nil)
        @loading_text = loading_text
        @source = source
        @classes = classes
        @test_selector = test_selector
      end
    end
  end
end
