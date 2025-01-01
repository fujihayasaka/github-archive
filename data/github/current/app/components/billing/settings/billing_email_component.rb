# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class BillingEmailComponent < ApplicationComponent
      attr_reader :target, :form, :label, :hint, :error, :disabled, :html_class, :test_selector_text, :data

      def initialize(target:, form:, label: "Billing email", hint: "", error: nil, data: {}, disabled: false, html_class: "form-control", test_selector_text: "")
        @target = target
        @form = form
        @label = label
        @hint = hint
        @error = error
        @disabled = disabled
        @html_class = html_class
        @data = data
        @test_selector_text = test_selector_text
      end

      def render?
        target.organization? || target.business?
      end
    end
  end
end
