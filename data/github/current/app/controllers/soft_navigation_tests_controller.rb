# typed: true
# frozen_string_literal: true

require "react_payload"

class SoftNavigationTestsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  layout "layouts/soft_navigation_tests"

  before_action :require_feature_flags
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  class BasePayload < ReactPayload::Base
    def route_id
      raise NotImplementedError, "Subclasses must implement the `route_id` method"
    end

    sig { params(message: String).void }
    def initialize(message)
      @message = message
      @server_time = Time.now
    end

    def payload
      {
        someField:  @message,
        serverTime: @server_time,
      }
    end
  end

  class LayoutPayload < BasePayload
    def route_id
      "layoutRoute"
    end
  end

  class IndexPayload < BasePayload
    def route_id
      "indexRoute"
    end
  end

  class ShowPayload < BasePayload
    def route_id
      "showRoute"
    end
  end

  def index
    title = "Soft Navigation Tests"
    payload = IndexPayload.new("Index")
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new("Layout")
        render_react_html(
          app_name: "navigation-tests",
          title: title, payload: payload,
          nested_payloads: [layout_payload],
          turbo: turbo_args
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def show
    param = params[:param]

    return render_404 if param == "404"

    title = "Show (#{param})"
    payload = ShowPayload.new("Show")
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new("Layout")
        render_react_html(
          app_name: "navigation-tests",
          title: title, payload: payload,
          nested_payloads: [layout_payload],
          turbo: turbo_args
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def other_index # rubocop:disable GitHub/UseRestfulActions
    title = "Other Soft Navigation Tests"
    payload = IndexPayload.new("Other Index")
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new("Other Layout")
        render_react_html(
          app_name: "navigation-tests-other",
          title: title, payload: payload,
          nested_payloads: [layout_payload],
          turbo: turbo_args
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def other_show # rubocop:disable GitHub/UseRestfulActions
    param = params[:param]
    title = "Other Show (#{param})"
    payload = ShowPayload.new("Other Show")
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new("Other Layout")
        render_react_html(
          app_name: "navigation-tests-other",
          title: title, payload: payload,
          nested_payloads: [layout_payload],
          turbo: turbo_args
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def layout # rubocop:todo GitHub/UseRestfulActions
    payload = LayoutPayload.new("Layout")
    respond_to do |format|
      format.json do
        render_react_json(payload: payload)
      end
    end
  end

  def other_layout # rubocop:todo GitHub/UseRestfulActions
    payload = LayoutPayload.new("Other Layout")
    respond_to do |format|
      format.json do
        render_react_json(payload: payload)
      end
    end
  end

  private

  def turbo_args
    {
      id: "soft-nav-tests-frame",
      target: "_top",
      action: "advance",
      class: "d-flex flex-auto"
    }
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_flags
    render_404 unless current_user.feature_enabled?(:react_sandbox)
  end
end
