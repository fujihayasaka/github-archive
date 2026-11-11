# typed: true
# frozen_string_literal: true

class StatusLolrailsController < ApplicationController
  # As of 2019-04-16, status_lolrails is averaging around 510 rq/sec, or a bit
  # under 3% of total requests
  set_statsd_sample_rate 0.01, only: :index

  before_action :disable_hydro_request_logging, only: [:index]

  skip_around_action :limit_concurrent_requests, only: [:index]
  skip_around_action :with_user_timezone, only: [:index]
  skip_around_action :check_search_index_override, only: [:index]
  skip_around_action :staff_api_insights_instrumentation, only: [:index]
  skip_around_action :staff_external_service_profiler, only: [:index]
  skip_around_action :staff_mysql_instrumentation, only: [:index]
  skip_around_action :mysql_instrumentation_for_sampled_requests, only: [:index]
  skip_around_action :staff_platform_loader_tracker, only: [:index]
  skip_around_action :staff_rails_instrumentation, only: [:index]
  skip_before_action :employee_only_unicorn, only: [:index]
  skip_before_action :enable_cookie_consent, only: [:index]
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :setup_audit_context, only: [:index]
  skip_before_action :do_feature_preload, only: [:index]
  skip_before_action :block_anon_actor_for_endpoint, only: [:index]
  skip_before_action :block_ip_address, only: [:index]
  # Skip session and rate limiting checks to prevent memcached calls for health checks
  skip_before_action :touch_user_session
  skip_before_action :initialize_hydro_context
  skip_before_action :check_rate_limit_early

  if GitHub.single_business_environment?
    skip_before_action :first_run_check, only: [:index]
    skip_before_action :license_expiration_check, only: [:index]
    skip_before_action :override_referrer_policy
  end

  # Used as a health check by several load balancers. The first respond_to block
  # is rendered when the Accept header is empty, which is what happens when
  # using `curl` by default. There's currently not a test for this bevaior, so
  # please verify manually. See https://github.com/github/github/pull/35391 and
  # https://github.com/github/github/pull/35389 for context.
  def index
    # An early hook to return a 503 instead of success when we're running on kube
    # but the last worker hasn't started and dropped the ready file. This allows
    # kube readiness checks to fail until the last worker comes up.
    if GitHub.kube? && !File.exist?(GitHub.kube_workers_ready_file)
      render plain: "Workers are not yet ready.", status: 503
      return
    end

    respond_to do |f|
      f.html do
        render "site/status", layout: false
      end
      f.json do
        data = { status: "ok" }
        data[:configuration_id] = GitHub.configuration_id if GitHub.configuration_id
        render json: data
      end
    end
  end

  private

  # Disable default rate limiting for health check endpoints to prevent memcached calls.
  # This ensures that new controller-level rate limiters added to ApplicationController
  # will automatically exclude status endpoints without requiring manual configuration.
  def endpoint_rate_limited_by_default?
    false
  end
end
