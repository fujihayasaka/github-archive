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

    if error.present?
      flash[:error] = "Authentication with Azure failed. (#{error})"
      redirect_to settings_enterprises_path
      return
    end

    begin
      state_hash = state_to_hash(state: params[:state])
    rescue JSON::JSONError
      flash[:error] = "Failed decoding state from Azure"
      redirect_to settings_enterprises_path
      return
    end

    business_slug = state_hash[:business_slug]
    explicit_tenant_selected = state_hash[:explicit_tenant_selected] || false
    redirect_path = state_hash[:redirect_path]
    host_name = state_hash[:host_name]

    params = {
      slug: business_slug,
      redirect_path: redirect_path,
      oauth_code: code,
      explicit_tenant_selected: explicit_tenant_selected
    }

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

    approved_hostnames = [/\A([\w-]+\.)?github\.com(:\d+)?\z/, /\A([\w-]+\.)?ghe\.com(:\d+)?\z/, /\A([\w-]+\.)?ghe\.localhost(:\d+)?\z/, /\A([\w-]+\.)?github\.localhost(:\d+)?\z/,]
    approved_hostnames.any? { |approved_hostname| host_name.match?(approved_hostname) }
  end
end
