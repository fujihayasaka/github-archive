# typed: true
# frozen_string_literal: true

class Site::BaseController < ApplicationController
  include AnalyticsHelper
  include Site::MicrosoftAnalyticsDependency

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :disable_in_enterprise_and_proxima
  before_action :disable_color_modes
  before_action :disable_header_redesign

  layout "site"

  javascript_bundle "marketing"
  stylesheet_bundle "site"

  private

  def disable_in_enterprise_and_proxima
    render_404 if GitHub.single_or_multi_tenant_enterprise?
  end
end
