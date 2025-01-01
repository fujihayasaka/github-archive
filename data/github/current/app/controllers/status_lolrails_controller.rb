# typed: true
# frozen_string_literal: true

require "asset_bundles_helper"

class StatusLolrailsController < ApplicationController
  ASSET_PATH = Rails.root.join("public", "assets")
  # As of 2019-04-16, status_lolrails is averaging around 510 rq/sec, or a bit
  # under 3% of total requests
  set_statsd_sample_rate 0.01, only: :index

  before_action :disable_hydro_request_logging, only: [:index]

  skip_before_action :employee_only_unicorn, only: [:index]
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  if GitHub.single_business_environment?
    skip_before_action :first_run_check, only: [:index]
    skip_before_action :license_expiration_check, only: [:index]
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

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

    return render plain: "Failed to render required client bundles.", status: 503 unless verify_assets

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

  def verify_assets
    verify_manifest_keys && verify_files_exists
  end

  # This will build all the required HTML tags for the page. If any of the
  # required bundles are missing on the manifest, it will raise a KeyError.
  def verify_manifest_keys
    helpers.stylesheet_required_bundles.each do |bundle|
      helpers.stylesheet_bundle(bundle)
    end
    helpers.controller_javascript_bundles

    true
  rescue KeyError
    false
  end

  # This will ensure all bundle files actually exist in disk. Since we upload
  # those to the CDN, this should ensure that the necessary files are present.
  def verify_files_exists
    # dev mode doesn't persist files to disk.
    return true if Rails.env.development?

    helpers.expanded_required_bundles.each do |bundle|
      return false unless File.exist?(ASSET_PATH.join(bundle[:src]))
    end

    helpers.expanded_required_stylesheets.each do |bundle|
      return false unless File.exist?(ASSET_PATH.join(bundle[:src]))
    end

    true
  end
end
