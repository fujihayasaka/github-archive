# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

require "react_payload"
require "scribe"
require "monolith-twirp-scribe-recaps"

class Scribe::RecapsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :destroy]

  before_action :parse_json_params
  before_action :require_feature_flags
  before_action :login_required
  before_action :load_owner
  before_action :load_project
  before_action :ensure_project_exists
  before_action :ensure_user_has_access

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Scribe::RecapsController#create",
    "Scribe::RecapsController#destroy",
  ].freeze

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Collab, ApplicationRecord::Repositories, ApplicationRecord::Memex

  class IndexPayload < ReactPayload::Base
    def route_id
      "scribeRecapsRoute"
    end

    def initialize(recaps:)
      @recaps = recaps
    end

    def payload
      {
        recaps: @recaps
      }
    end
  end

  def index
    title = "Recaps"

    payload = IndexPayload.new(
      recaps: load_recaps
    )

    respond_to do |format|
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  class CreatePayload < ReactPayload::Base
    def route_id
      "scribeCreateRecapRoute"
    end

    def initialize(success:)
      @success = success
    end

    def payload
      {
        success: @success
      }
    end
  end

  def create
    title = "Recaps"
    success = true

    success = generate_scribe_recap if scribe_enabled?

    payload = CreatePayload.new(success:)

    respond_to do |format|
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  class DestroyPayload < ReactPayload::Base
    def route_id
      "scribeDestroyRecapRoute"
    end

    def initialize(success:)
      @success = success
    end

    def payload
      {
        success: @success
      }
    end
  end

  def destroy
    title = "Recaps"
    success = true

    success = delete_scribe_recap if scribe_enabled?

    payload = DestroyPayload.new(success:)

    respond_to do |format|
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  private

  def generate_scribe_recap
    GitHub.scribe_client.generate_project_recap(
      user: current_user,
      project: @project,
      view_id: 0,
      filter_query: params[:filter_query].to_s,
      prompt_options: params[:prompt_options]&.permit(:report_prompt, :insight_prompt)&.to_h,
      timezone: cookies[:tz].to_s,
    )

    true
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.recaps.create", tags: ["success:false"])
    false
  end

  def delete_scribe_recap
    GitHub.scribe_client.delete_recap(
      user: current_user,
      recap_id: params[:id].to_i,
    )

    true
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.recaps.destroy", tags: ["success:false"])
    false
  end

  def load_recaps
    return [] unless scribe_enabled?

    scribe_recaps.map do |recap|
      recap_hash = recap.to_h
      # Convert protobuf timestamps to ISO8601 strings
      recap_hash[:created_at] = Time.at(recap.created_at.seconds) if recap.created_at
      recap_hash[:start_time] = Time.at(recap.start_time.seconds) if recap.start_time
      recap_hash[:end_time] = Time.at(recap.end_time.seconds) if recap.end_time
      recap_hash
    end
  end

  memoize def scribe_recaps
    response = GitHub.scribe_client.get_recaps(
      user: current_user,
      project_id: @project.id,
      view_id: 0,
    )

    response&.recaps || []
  end

  def load_project
    @project = @owner&.memex_projects&.active_projects&.find_by(number: params[:project_number])
  end

  def load_owner
    @owner = case params[:owner_type]
    when "orgs"
      Organization.find_by_login(params[:owner_id])
    when "users"
      User.find_by_login(params[:owner_id])
    end
  end

  def ensure_user_has_access
    return unless scribe_enabled?

    render_404 unless @project&.viewer_can_read?(current_user)
  end

  def ensure_project_exists
    return unless scribe_enabled?

    render_404 unless @owner.present? && @project.present?
  end

  def require_feature_flags
    render_404 unless FeatureFlag.vexi.enabled?(:scribe_reporting_enabled, current_user, default: false)
  end

  def scribe_enabled?
    GitHub.scribe_enabled?(user: current_user)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    scribe_enabled? ? (@project || current_user) : current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    scribe_enabled? ? (@project || current_user) : current_user
  end
end
