# typed: true
# frozen_string_literal: true

class Attachments::LegacyUserAssetsController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    asset = UserAsset.where(
      guid: params[:guid],
      user_id: params[:user],
      repository_id: current_repository.id,
      state: 1, # uploaded
    ).first

    return render_404 unless asset
    return render_404 if asset.using_new_url?

    redirect_to asset.redirect_url(actor: the_actor)
  end

  protected

  # Override ApplicationController#authentication_methods to accept
  # an alternative auth method. The alternative auth method lets us
  # authenticate a session-less logged in request for assets while
  # using clients like GitHub Desktop etc.
  def authentication_methods
    return super unless header_auth_allowed?

    super || login_from_authorization_header_auth
  end

  private

  # Determines whether header authentication is allowed for the current action.
  def header_auth_allowed?
    %w{show}.include?(action_name)
  end

  def the_actor
    # For GHES installations where the private mode is turned off, we fallback to the ghost user for calls made to
    # public resources from logged out users.
    return current_user || User.ghost if GitHub.storage_cluster_enabled?
    current_user
  end
end
