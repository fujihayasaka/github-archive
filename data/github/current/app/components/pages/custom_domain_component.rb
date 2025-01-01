# typed: true
# frozen_string_literal: true

module Pages
  class CustomDomainComponent < ApplicationComponent
    attr_reader :repository

    def initialize(repository:, state:, warning: nil, primary_check: nil, alt_check: nil)
      @repository = repository
      @state = state
      @warning = warning
      @primary_check = primary_check
      @alt_check = alt_check
    end

    def state_message
      case @state
      when :pending, :queued
        "DNS Check in Progress"
      when :both_valid, :valid
        "DNS check successful"
      when :primary_only
        "DNS valid for primary"
      when :invalid, :both_invalid, :alternate_only
        "DNS check unsuccessful"
      end
    end

    def state_class
      case @state
      when :pending, :queued, :primary_only
        "color-fg-attention"
      when :both_valid, :valid
        "color-fg-success"
      when :invalid, :both_invalid, :alternate_only
        "color-fg-danger"
      end
    end

    def should_show_error?
      return false if @state == :disabled
      (@repository.has_gh_pages? || @repository.page.workflow_build_enabled?) &&
      (![:valid, :both_valid, :pending].include?(@state) || @warning.present?)
    end

    def should_show_ascii_domain?
      @repository.page.cname && @repository.page.cname != @repository.page.display_cname
    end
  end
end
