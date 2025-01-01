# typed: true
# frozen_string_literal: true

class Settings::LinkRequestsController < ApplicationController
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1, only: [:new]
  before_action :check_feature_flag

  def new
    render "settings/email_subscriptions/link_request"
  end

  def create
    api_response = cpm_api.get_authentication_url(params[:email])

    if api_response[:url]
      deliver_email(api_response[:url])

      flash[:notice] = "We've sent a link to your email to manage this communication request."
      redirect_to new_settings_link_request_path
    else
      flash[:error] = "We're having trouble sending your communication request. Please try again."
      redirect_to new_settings_link_request_path
    end
  end

  private

  def deliver_email(url)
    temporary_url = temporary_modify_link(url)
    query_string = query_string_from(url)
    query_params = query_from(url)

    EmailSubscriptionsMailer.preferences_center_access_link(params[:email], temporary_url).deliver_later

    # Unsubscribe & Opt-In links are generated upon delivery of marketing emails.
    # There is no way for GitHub to generate double opt-in or unsubscribe links.
    # As such, for testing & development purposes, these links are assembled from the unsubscribeAll link.
    if GitHub.email_preferences_center_elections_email_enabled?
      # topics_available exists b/c we can only unsubscribe from topics the user is already subscribed to.
      topics_available = cpm_api.get_topic_settings_from_cpm_link(query_params)[:data][:topics]
      topics_available = topics_available.filter { |topic| topic[:canContact] != false }
      EmailSubscriptionsMailer.opt_in_and_unsubscribe_links(params[:email], query_string, topics_available).deliver_later
    end
  end

  memoize def cpm_api
    Cpm::RestApiClient.new
  end

  # pages meant to be accessed anonymously, authorization not necessary
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def check_feature_flag
    render_404 unless feature_enabled_globally_or_for_current_user?(:email_preference_center)
  end

  def query_string_from(url)
    uri = URI.parse(url)
    Rack::Utils.parse_query(uri.query).to_query
  end

  def query_from(url)
    uri = URI.parse(url)
    Rack::Utils.parse_query(uri.query)
  end

  # Basis for temp: The CPM API root for this project has not been set up.
  def temporary_modify_link(url)
    query = query_string_from(url)
    "#{GitHub.url}#{settings_email_subscriptions_path}?#{query}"
  end
end
