# typed: true
# frozen_string_literal: true

# This is intendended to be used as a base class for controllers that are able to skip
# potentially expensive filters, for example - in cases where the response does not
# render HTML so won't display banners or staff bars.
module ApplicationController::MinimalApplicationDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  SKIPPABLE_AROUND_FILTERS = [
    :check_search_index_override,
    :staff_api_instrumentation,
    :staff_external_service_profiler,
    :staff_mysql_instrumentation,
    :staff_rails_instrumentation,
  ]

  SKIPPABLE_BEFORE_FILTERS = [
    :account_2fa_requirement_banner,
    :account_2fa_requirement_interrupt,
    :add_dreamlifter_csp_exceptions,
    :add_insights_csp_exceptions,
    :add_origin_trial_header,
    :add_s3_storage_csp_exceptions,
    :ask_the_gatekeeper,
    :cap_pagination,
    :check_rate_limit,
    :cpq_check,
    :disable_session,
    :do_feature_preload,
    :employee_only_unicorn,
    :enforce_oauth_scope,
    :require_two_factor_checkup,
    :set_default_locale,
    :set_default_nav_breadcrumb,
    :set_employee_cookie,
    :set_path_and_name,
    :set_pjax_url,
    :set_rails_version_header,
    :set_site_admin_and_employee_status,
    :set_vary_pjax,
    :set_vary_turbo,
    :skip_mc_check,
    :touch_user_session,
    :trusted_types_enforce_via_param,
  ]

  SKIPPABLE_AFTER_FILTERS = [
    :block_non_xhr_json_responses,
    :sanitize_pjax_redirects,
    :set_color_mode_cookie,
    :set_html_safe,
    :set_pjax_version,
  ]

  included do
    T.bind(self, T.class_of(ApplicationController))

    SKIPPABLE_AROUND_FILTERS.each { |filter| skip_around_action filter }

    SKIPPABLE_BEFORE_FILTERS.each { |filter| skip_before_action filter }

    SKIPPABLE_AFTER_FILTERS.each { |filter| skip_after_action filter }
  end

  private

  def preview_features?
    false
  end

  def trace_employee_login
    "NOT_TRACKED"
  end
end
