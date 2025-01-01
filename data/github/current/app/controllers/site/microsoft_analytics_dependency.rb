# typed: true
# frozen_string_literal: true

module Site::MicrosoftAnalyticsDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { ApplicationController }

  include GitHub::Memoizer

  private

  memoize def enable_microsoft_analytics
    return if GitHub.single_or_multi_tenant_enterprise?

    @microsoft_analytics_enabled = feature_enabled_globally_or_for_current_user?(:marketing_microsoft_analytics)
  end

  def add_microsoft_analytics_csp_exceptions
    return unless @microsoft_analytics_enabled

    csp_exceptions = {
      connect_src: ["browser.events.data.microsoft.com"],
    }

    SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
  end
end
