# typed: true
# frozen_string_literal: true

require "github/anthropic/user_profiles_client"

class Stafftools::AnthropicUserIdsController < StafftoolsController
  OWNER_CLASSES = {
    "Business" => ::Business,
    "Organization" => ::Organization,
    "User" => ::User,
  }.freeze

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::AnthropicUserIdsController#create",
  ].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show, :create]

  before_action :dotcom_required

  def show
    profile = anthropic_profile_from_params
    anthropic_user_id = profile&.anthropic_id.presence || anthropic_user_id_param

    if anthropic_user_id.blank?
      flash[:error] = "Anthropic User ID can't be blank."
      return redirect_back_with_stafftools_fallback
    end

    response = user_profiles_client.get_user_profile(anthropic_user_id)

    if response.success?
      flash[:notice] = profile_status_message(response.body)
    else
      flash[:error] = error_message_for(response, action: "lookup", anthropic_user_id: anthropic_user_id)
    end

    redirect_back_with_stafftools_fallback
  rescue Faraday::Error => e
    flash[:error] = e.message
    redirect_back_with_stafftools_fallback
  end

  def create
    return refresh_profile_status if refresh_requested?

    owner = owner_from_params
    request_name = params[:name].to_s.strip
    request_external_id = params[:external_id].to_s.strip

    if owner.nil?
      flash[:error] = "Owner can't be blank."
      return redirect_back_with_stafftools_fallback
    end

    if request_name.blank?
      flash[:error] = "Name can't be blank."
      return redirect_back_with_stafftools_fallback
    end

    if request_external_id.blank?
      flash[:error] = "External ID can't be blank."
      return redirect_back_with_stafftools_fallback
    end

    response = user_profiles_client.create_user_profile(
      name: request_name,
      external_id: request_external_id,
    )

    if response.success?
      profile = persist_profile!(owner: owner, body: response.body, external_id: request_external_id)
      created_profile_id = profile.anthropic_id.to_s
      flash[:notice] = if created_profile_id.present?
        "Created Anthropic user profile #{created_profile_id}."
      else
        "Created Anthropic user profile."
      end
    else
      flash[:error] = error_message_for(response, action: "create")
    end

    redirect_back_with_stafftools_fallback
  rescue Faraday::Error => e
    flash[:error] = e.message
    redirect_back_with_stafftools_fallback
  end

  private

  memoize def user_profiles_client
    GitHub::Anthropic::UserProfilesClient.new
  end

  def anthropic_user_id_param
    params[:anthropic_user_id].to_s.strip
  end

  def anthropic_profile_from_params
    owner = owner_from_params
    return if owner.nil?

    ::Copilot::AnthropicUserProfile.for_owner(owner)
  end

  def refresh_requested?
    params[:refresh].present?
  end

  def refresh_profile_status
    profile = anthropic_profile_from_params
    anthropic_user_id = profile&.anthropic_id.to_s

    if anthropic_user_id.blank?
      flash[:error] = "Anthropic User ID can't be blank."
      return redirect_back_with_stafftools_fallback
    end

    response = user_profiles_client.get_user_profile(anthropic_user_id)

    if response.success?
      profile.update_from_api_response!(response.body)
      flash[:notice] = profile_status_message(response.body)
    else
      flash[:error] = error_message_for(response, action: "lookup", anthropic_user_id: anthropic_user_id)
    end

    redirect_back_with_stafftools_fallback
  rescue Faraday::Error => e
    flash[:error] = e.message
    redirect_back_with_stafftools_fallback
  end

  def owner_from_params
    owner_type = params[:owner_type].to_s.strip
    owner_id = params[:owner_id].to_i
    owner_class = OWNER_CLASSES[owner_type]

    return if owner_class.nil? || owner_id <= 0

    owner_class.find_by(id: owner_id)
  end

  def persist_profile!(owner:, body:, external_id: nil)
    profile = ::Copilot::AnthropicUserProfile.find_or_initialize_by(
      owner_id: owner.id,
      owner_type: owner.class.name,
    )
    profile.external_id = external_id if external_id.present?
    profile.update_from_api_response!(body)
    profile
  end

  def error_message_for(response, action:, anthropic_user_id: nil)
    body = response.body
    error = body["error"] if body.is_a?(Hash)
    message = if error.is_a?(Hash)
      error["message"] || error[:message]
    elsif error.present?
      error
    elsif body.is_a?(Hash)
      body["message"] || body[:message]
    end

    if action == "lookup" && response.status == 404 && anthropic_user_id.present?
      "Anthropic user profile #{anthropic_user_id} was not found."
    elsif message.present?
      "Anthropic #{action} request failed with status #{response.status}: #{message}"
    else
      "Anthropic #{action} request failed with status #{response.status}."
    end
  end

  def profile_status_message(profile)
    profile_id = profile["id"].presence || "unknown"
    details = []

    name = profile["name"].presence
    external_id = profile["external_id"].presence
    trust_grants = profile["trust_grants"]
    cyber_preview = trust_grants.is_a?(Hash) ? trust_grants["cyber_preview"] : nil

    details << "name: #{name}" if name.present?
    details << "external ID: #{external_id}" if external_id.present?
    details << "cyber preview: #{cyber_preview ? "approved" : "not approved"}"

    if details.any?
      "Anthropic user profile #{profile_id} found (#{details.join(", ")})."
    else
      "Anthropic user profile #{profile_id} found."
    end
  end

  def redirect_back_with_stafftools_fallback
    redirect_back(fallback_location: stafftools_path)
  end
end
