# typed: true
# frozen_string_literal: true

class Api::AnnouncementBanners < Api::App
  include ReceiveSchemaWithOpenApi

  ###############
  # REPOS
  ###############

  get "/repositories/:repository_id/announcement", operation_id: "announcement-banners/get-announcement-banner-for-repo" do
    repo = find_repo!
    business = repo.business

    ensure_repo_level_feature_flag_enabled business

    control_access :read_announcement_banner,
      resource: repo,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_get repo
  end

  patch "/repositories/:repository_id/announcement", operation_id: "announcement-banners/set-announcement-banner-for-repo" do
    repo = find_repo!
    business = repo.business

    ensure_repo_level_feature_flag_enabled business

    control_access :write_announcement_banner,
      resource: repo,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_patch repo
  end

  delete "/repositories/:repository_id/announcement", operation_id: "announcement-banners/remove-announcement-banner-for-repo" do
    repo = find_repo!
    business = repo.business

    ensure_repo_level_feature_flag_enabled business

    control_access :write_announcement_banner,
      resource: repo,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_delete repo
  end

  ###############
  # ORGS
  ###############

  get "/organizations/:organization_id/announcement", operation_id: "announcement-banners/get-announcement-banner-for-org" do
    org = find_org!
    business = org.business

    control_access :read_announcement_banner,
      resource: org,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_get org
  end

  patch "/organizations/:organization_id/announcement", operation_id: "announcement-banners/set-announcement-banner-for-org" do
    org = find_org!
    business = org.business

    control_access :write_announcement_banner,
      resource: org,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_patch org
  end

  delete "/organizations/:organization_id/announcement", operation_id: "announcement-banners/remove-announcement-banner-for-org" do
    org = find_org!
    business = org.business

    control_access :write_announcement_banner,
      resource: org,
      business: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_delete org
  end

  ###############
  # ENTERPRISES
  ###############

  get "/enterprises/:enterprise_id/announcement", operation_id: "announcement-banners/get-announcement-banner-for-enterprise" do
    deliver_error! 404 if GitHub.enterprise?

    business = find_enterprise!

    control_access :read_announcement_banner,
      resource: business,
      business: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    handle_get business
  end

  patch "/enterprises/:enterprise_id/announcement", operation_id: "announcement-banners/set-announcement-banner-for-enterprise" do
    deliver_error! 404 if GitHub.enterprise?

    business = find_enterprise!

    control_access :write_announcement_banner,
      resource: business,
      business: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    handle_patch business
  end

  delete "/enterprises/:enterprise_id/announcement", operation_id: "announcement-banners/remove-announcement-banner-for-enterprise" do
    deliver_error! 404 if GitHub.enterprise?

    business = find_enterprise!

    control_access :write_announcement_banner,
      resource: business,
      business: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    handle_delete business
  end

  private

  def handle_get(owner)
    banner = EnterpriseBanner.active.find_by(owner: owner)
    deliver_banner_if_exists banner
  end

  def handle_patch(owner)
    data = receive_with_openapi
    existing_banner = EnterpriseBanner.find_by(owner: owner)

    new_banner = EnterpriseBanner.new(owner: owner)
    new_banner.message = data["announcement"] if data.key?("announcement")
    new_banner.expires_at = data["expires_at"].presence if data.key?("expires_at")

    if data.key?("user_dismissible")
      new_banner.dismissible = data["user_dismissible"].presence || false
    elsif !existing_banner.nil?
      new_banner.dismissible = existing_banner.dismissible
    else
      new_banner.dismissible = false
    end

    if !existing_banner.nil? && existing_banner == new_banner
      deliver_banner_if_exists existing_banner
    elsif new_banner.valid?
      new_banner.upsert_for(owner, current_user)
      deliver_banner_if_exists new_banner
    else
      deliver_error!(400, message: new_banner.errors.full_messages.to_sentence)
    end
  end

  def handle_delete(owner)
    EnterpriseBanner.clear_for(owner, current_user)
    deliver_empty status: 204
  end

  def ensure_repo_level_feature_flag_enabled(business)
    deliver_error! 404 if !GitHub.flipper[:enterprise_banners_repo_level].enabled?(business)
  end

  def deliver_banner_if_exists(banner)
    deliver :enterprise_announcement_hash, {
      announcement: banner&.message.presence,
      expires_at: banner&.expires_at.presence,
      user_dismissible: banner&.dismissible.presence
    }
  end
end
