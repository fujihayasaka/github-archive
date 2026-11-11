# typed: true
# frozen_string_literal: true

class Businesses::AzureAuthCallbackController < ApplicationController
  include Businesses::AzureSubscriptions

  # CAP not required, this only redirects to a static page for non-employees
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:callback]

  def callback # rubocop:todo GitHub/UseRestfulActions
    code = params[:code]
    error = params[:error]
    state = params[:state]

    if error.present?
      flash[:error] = "Authentication with Azure failed. (#{error})"
      redirect_to settings_enterprises_path
      return
    elsif state.blank?
      flash[:error] = "Missing state from Azure"
      redirect_back(fallback_location: "/")
      return
    end

    begin
      state_hash = state_to_hash(state: params[:state], validate: false)
    rescue JSON::JSONError
      flash[:error] = "Failed decoding state from Azure"
      redirect_to settings_enterprises_path
      return
    rescue Billing::AzureOauthStateManagement::AzureStateValidationError
      flash[:error] = "Authentication request invalid or expired. Please try again."
      redirect_to settings_enterprises_path
      return
    end

    business_slug = state_hash[:business_slug]
    state_hash[:oauth_code] = code
    # We can't use hash_to_state here because it would generate a new session token
    # in the current session, which may be different from the original session.
    # In Proxima environments, the flow crosses domains:
    # 1. User starts on tenant.github.com (generates token A)
    # 2. Azure redirects to github.com/enterprises/oauth_callback (different session)
    # 3. We redirect back to tenant.github.com (needs original token A, not new token B)
    # hash_to_state would generate a new token if there isn't one already in session which we don't want to do here
    state = encode_signed_state(hash: state_hash)
    params = {
      slug: business_slug,
      azure_state: state
    }

    host_name = state_hash[:host_name]
    if host_name.present?
      # for multitenant environments AKA Proxima, we need to pass the host name so Azure redirects will work when there is a subdomain.
      # using the host parameter with a Rails url helper will explicitly set a host name for the redirect.
      if valid_host_name?(host_name: host_name)
        params[:host] = host_name
      else
        GitHub.logger.info(
          "Did not redirect after Azure auth because of an invalid host name",
          "code.namespace" => self.class.name,
          "gh.business.slug" => business_slug,
          "gh.app.host" => host_name,
        )
        flash[:error] = "There was an error redirecting after Azure authentication."
        return redirect_to settings_enterprises_path
      end
    end
    GitHub.logger.info("Redirecting after Azure auth", "code.namespace" => self.class.name, "gh.business.slug" => business_slug, "gh.app.host" => host_name || "nil")
    redirect_to billing_payment_information_authenticate_enterprise_url(**params)
  end

  private

  def valid_host_name?(host_name:)
    return false if host_name.blank?

    approved_hostnames = [/\A([\w-]+\.)?github\.com(:\d+)?\z/, /\A([\w-]+\.)?ghe\.com(:\d+)?\z/]
    if Rails.env.development?
      approved_hostnames += [/\A([\w-]+\.)?ghe\.localhost(:\d+)?\z/, /\A([\w-]+\.)?github\.localhost(:\d+)?\z/]
    end
    approved_hostnames.any? { |approved_hostname| host_name.match?(approved_hostname) }
  end
end
