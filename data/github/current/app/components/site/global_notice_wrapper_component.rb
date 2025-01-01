# typed: true
# frozen_string_literal: true

module Site
  class GlobalNoticeWrapperComponent < ApplicationComponent
    def initialize(viewer:, hide_two_factor_recover_code_warning: false, hide_email_verification_warning: false, hide_security_warning: false)
      @hide_two_factor_recover_code_warning = hide_two_factor_recover_code_warning
      @hide_email_verification_warning = hide_email_verification_warning
      @hide_security_warning = hide_security_warning
      @viewer = viewer
    end

    def call
      return render_old_global_notice if GitHub.enterprise?
      global_notice_next_component = Site::GlobalNoticeNextComponent.new(
        viewer: @viewer,
        hide_two_factor_recover_code_warning: @hide_two_factor_recover_code_warning,
        hide_email_verification_warning: @hide_email_verification_warning,
        hide_security_warning: @hide_security_warning
      )
      render global_notice_next_component
    end

    def render_in(*)
      super
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      raise unless Rails.env.production?

      Failbot.report(e)
      GitHub.dogstats.increment("global_notice_wrapper_component.error")
      ""
    end

    private

    def render_old_global_notice
      render(Site::GlobalNoticeComponent.new(
        hide_two_factor_recover_code_warning: @hide_two_factor_recover_code_warning,
        hide_email_verification_warning: @hide_email_verification_warning
      ))
    end
  end
end
