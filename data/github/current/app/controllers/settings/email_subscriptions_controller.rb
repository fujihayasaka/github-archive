# typed: true
# frozen_string_literal: true

# Allows a user to access and control their current marketing email subscriptions
class Settings::EmailSubscriptionsController < ApplicationController
  include GitHub::Memoizer
  include UrlHelper

  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1, # Feature flag lookup
    # Clusters used for logged in state
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index]

  before_action :check_feature_flag

  before_action :set_topic_id, only: [:unsubscribe]
  before_action :handle_topic_or_request_redirect, only: [:double_opt_in]
  before_action :fetch_settings, only: [:unsubscribe, :update]
  before_action :ensure_auth_methods_present, only: [:update]

  allow_verified_fetch only: [:fetch_topics_by_cpm_params, :fetch_topics_by_email]
  before_action :ensure_fe_request, only: [:fetch_topics_by_cpm_params, :fetch_topics_by_email]

  DEFAULT_NEW_LINK_REQUEST_MESSAGE = "Something went wrong, request a new link to manage your email preferences. Please contact our support if problem persists."

  # List all publications and the current subscription status of each for the user
  def index
    email = params[:email]
    if UserEmail.email_addresses_for(current_user, verified: true).include?(params[:email])
      render "settings/email_subscriptions/index", locals: {
        email: email
      }
    elsif required_cpm_link_params_present?
      render "settings/email_subscriptions/index", locals: {
        cpm_params: cpm_link_params
      }
    else
      redirect_to_request_new_link
    end
  end

  # Update contact point based on form output from index
  # rubocop:disable GitHub/UseRestfulActions
  def update
    unsubscribe_ids = []

    params[:topics].each do |key, value|
      unsubscribe_ids << key if value == "false"
    end

    if unsubscribe_ids.empty?
      flash[:error] = "No topics found to unsubscribe. Try again."
      return redirect_back(fallback_location: settings_email_subscriptions_path({ backlink: include_backlink? }))
    end

    resp = cpm_api.unsubscribe(@settings[:data], unsubscribe_ids)

    if resp[:timeout]
      handle_timeout
    elsif resp[:has_error]
      flash[:error] = resp[:message]
      redirect_back(fallback_location: settings_email_subscriptions_path({ backlink: include_backlink? }))
    else
      flash[:notice] = "Your preferences have been updated for #{@settings[:email]}"
      redirect_back(fallback_location: settings_email_subscriptions_path({ backlink: include_backlink? }))
    end
  end

  def double_opt_in
    opt_in_response = cpm_api.double_opt_in(params)

    if opt_in_response[:timeout]
      handle_timeout
    elsif opt_in_response[:topics]
      render "settings/email_subscriptions/opt_in_confirmation", locals: { topics: opt_in_response[:topics], email: opt_in_response[:decryptedContactValue], cpm_link_params: cpm_link_params }
    else
      message = opt_in_response[:message] || DEFAULT_NEW_LINK_REQUEST_MESSAGE
      redirect_to_request_new_link(message: message)
    end
  end

  def unsubscribe
    topic = @settings[:data][:topics].find { |topic| topic[:id] == @topic_id }

    if topic.nil?
      flash[:notice] = "You are already unsubscribed."
      return redirect_to settings_email_subscriptions_path(params: cpm_link_params, backlink: logged_in?)
    end

    unsub_response = cpm_api.unsubscribe(@settings[:data], [@topic_id])

    if unsub_response[:timeout]
      handle_timeout
    elsif unsub_response[:has_error]
      redirect_to_request_new_link(message: unsub_response[:message])
    else
      render "settings/email_subscriptions/unsubscribe_confirmation", locals: { topic: topic, email: @settings[:email], cpm_link_params: cpm_link_params }
    end
  end

  def fetch_topics_by_email
    email = params[:email]

    unless UserEmail.email_addresses_for(current_user, verified: true).include?(email)
      return render json: { has_error: true, new_link_required: true }
    end

    auth_url_resp = cpm_api.get_authentication_url(email)

    if auth_url_resp[:timeout]
      handle_timeout
    elsif auth_url_resp[:url].blank?
      render json: { has_error: true, new_link_required: true }
    else
      auth_url = URI.parse(auth_url_resp[:url])
      cpm_params = Rack::Utils.parse_query(auth_url.query)

      topic_settings_resp = cpm_api.get_topic_settings_from_cpm_link(cpm_params)
      if topic_settings_resp[:timeout]
        handle_timeout
      else
        render json: topic_settings_resp.merge({ cpm_params: cpm_params })
      end
    end
  end

  def fetch_topics_by_cpm_params
    unless required_cpm_link_params_present?
      return render json: { has_error: true, new_link_required: true }
    end

    resp = cpm_api.get_topic_settings_from_cpm_link(cpm_link_params)
    if resp[:timeout]
      handle_timeout
    else
      render json: resp
    end
  end

  private

  memoize def cpm_api
    Cpm::RestApiClient.new
  end

  # :backlink is used to conditional show a link to /settings/emails
  # It will only be present if the user came from /settings/emails
  def include_backlink?
    params[:backlink].present?
  end

  def cpm_link_params
    params.permit(:CTID, :ECID, :K, :D, :PID, :TID, :RID, :CMID, :MK, :backlink)
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def check_feature_flag
    render_404 unless feature_enabled_globally_or_for_current_user?(:email_preference_center)
  end

  def required_cpm_link_params_present?
    params[:CTID].present? && params[:ECID].present? && params[:K].present?
  end

  def ensure_auth_methods_present
    redirect_to_request_new_link unless required_cpm_link_params_present?
  end

  def set_topic_id
    if params[:TID].present?
      @topic_id = params[:TID]
    else
      redirect_to_request_new_link
    end
  end

  def handle_topic_or_request_redirect
    redirect_to_request_new_link unless params[:TID].present? || params[:RID].present?
  end

  def fetch_settings
    resp = cpm_api.get_topic_settings_from_cpm_link(params)

    if resp[:timeout]
      handle_timeout
    elsif resp[:has_error]
      redirect_to_request_new_link(message: resp[:message])
    else
      @settings = resp
    end
  end

  def ensure_fe_request
    redirect_to_request_new_link unless request&.xhr? && request&.format && request&.format.json?
  end

  def redirect_to_request_new_link(message: DEFAULT_NEW_LINK_REQUEST_MESSAGE, flash_type: :error)
    flash[flash_type] = message
    redirect_to new_settings_link_request_path
  end

  def handle_timeout
    if request&.format && request&.format.json?
      render json: { has_error: true, new_link_required: false }
    else
      redirect_to_request_new_link
    end
  end
end
