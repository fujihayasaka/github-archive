# typed: false
# frozen_string_literal: true

class AvatarsController < ApplicationController
  include AvatarHelper


  # The following actions do not require conditional access checks:
  # - show: serves `/settings/avatars/:id` and shows a user/orgs avatar,
  #   which is public information.
  skip_before_action :perform_conditional_access_checks, only: :show # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  before_action :ensure_viewer_can_edit_org_avatar, only: [:show, :update]
  before_action :find_avatar, only: [:show, :update]
  before_action :highlight_settings_sidebar, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    @primary_avatar = avatar_owner.primary_avatar

    respond_to do |format|
      format.html do
        render "avatars/show", layout: false, locals: { avatar: avatar }
      end
    end
  end

  def update
    if params[:op] == "destroy"
      flash[:notice] = "This #{human_avatar_name(avatar)} has been deleted."
      avatar.destroy
    else
      save_avatar_coordinates(avatar)
      PrimaryAvatar.set!(avatar, current_user, handle_previous_avatar: true)
      increment_avatar_stat
      flash[:notice] = "Your #{human_avatar_name(avatar)} has been updated.  It may take a few minutes to update across the site."
    end

    redirect_to settings_url_for_avatar_owner
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless avatar # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    owner = avatar.owner

    return owner.owner if owner.respond_to?(:owner)
    owner
  end

  def save_avatar_coordinates(avatar)
    return unless AVATAR_COORDINATES.all? { |attr| params[attr].present? }
    AVATAR_COORDINATES.each do |attr|
      avatar.send("#{attr}=", params[attr])
    end
    avatar.save!
  end

  AVATAR_COORDINATES = [:cropped_x, :cropped_y, :cropped_width, :cropped_height]

  memoize def avatar_owner
    if %w(show update).include?(params[:action])
      avatar&.owner
    elsif login = params[:organization]
      Organization.find_by_login(login.to_s)
    else
      current_user
    end
  end

  def ensure_viewer_can_edit_org_avatar
    if params[:organization]
      redirect_to "/settings/profile" unless avatar_owner&.avatar_editable_by?(current_user)
    end
  end

  memoize def avatar
    Avatar.find_by_id(params[:id].to_i)
  end

  # When destroying the avatar AssetUploadable#dereference_asset archives the asset
  # in after_destroy. This is considered transitively safe because of the Abilities
  # editable_by? check with current_user.
  def find_avatar
    redirect_to "/settings/profile" unless avatar&.editable_by?(current_user)
  end

  memoize def current_organization
    avatar_owner if avatar_owner&.respond_to?(:organization?) && avatar_owner.organization?
  end
  helper_method :current_organization

  def settings_url_for_avatar_owner
    case avatar_owner
    when Organization
      "/organizations/#{avatar_owner.display_login}/settings/profile"
    when User
      "/settings/profile"
    when OauthApplication
      oauth_app_redirect_path_for_avatar_owner
    when Integration
      gh_settings_app_path(avatar_owner)
    when Marketplace::Listing
      edit_description_marketplace_listing_path(avatar_owner)
    when Team
      edit_team_path(org: avatar_owner.organization, team_slug: avatar_owner.slug)
    when Business
      settings_profile_enterprise_path(avatar_owner)
    when RepositoryAction
      edit_repository_path(avatar_owner.repository)
    else
      raise ArgumentError, "Unknown settings url for avatar owner #{avatar_owner.class}"
    end
  end

  def oauth_app_redirect_path_for_avatar_owner
    oauth_app = avatar_owner
    if oauth_app.user.organization?
      settings_org_application_path(oauth_app.user, oauth_app)
    else
      settings_user_application_path(oauth_app)
    end
  end

  def highlight_settings_sidebar
    @selected_link = :avatar_settings
  end

  def increment_avatar_stat
    type_tag_value = avatar.owner_type.to_s.underscore
    # TODO - remove this stat once the conditional dogstats are populated
    GitHub.dogstats.increment("avatars.created", tags: ["type:#{type_tag_value}"])
    case avatar.owner_type
    when "OauthApplication"
      GitHub.dogstats.increment("avatar", tags: ["action:create", "via:oauth-application", "type:#{type_tag_value}"])
    when "Integration"
      GitHub.dogstats.increment("avatar", tags: ["action:create", "via:integration", "type:#{type_tag_value}"])
    end
  end
end
