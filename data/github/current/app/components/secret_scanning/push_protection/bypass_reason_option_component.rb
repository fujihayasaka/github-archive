# typed: true
# frozen_string_literal: true
module SecretScanning::PushProtection
  # View component for Secret Scanning - Bypass push protection
  class BypassReasonOptionComponent < ApplicationComponent
    def initialize(reason, label, description, form = "bypass-form")
      @reason = reason.to_s
      @label = label
      @description = description
      @form = form
    end

    private

    attr_reader :reason, :label, :description, :form
  end
end
