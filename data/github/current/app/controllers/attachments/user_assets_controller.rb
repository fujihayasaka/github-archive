# typed: true
# frozen_string_literal: true

class Attachments::UserAssetsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    return render_404 unless asset
    return render_404 if asset.upload_container_type == Gist.name # Gists have a separate controller and URL format
    return render_404 unless asset.has_access?(the_actor)

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

  memoize def asset
    UserAsset.where(
      guid: params[:guid],
      state: 1, # uploaded
    ).first
  end

  # Determines whether header authentication is allowed for the current action.
  def header_auth_allowed?
    %w{show}.include?(action_name) && asset && asset.repository
  end

  def the_actor
    # For GHES installations where the private mode is turned off, we fallback to the ghost user for calls made to
    # public resources from logged out users.
    return current_user || User.ghost if GitHub.storage_cluster_enabled?
    current_user
  end

  # Copied from `RepositoryControllerMethods`. Safe, since we only allow Oauth access
  # for assets associated with a repository
  def adequate_oauth_scope(scopes)
    Api::AccessControl.oauth_allows_access?(current_user, asset.repository) if asset
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless asset # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    if asset.repository
      # In case owner of repository is a deleted account, there will be no owner assigned to repository.
      # Thus, there will be no target for conditional access.
      return asset.repository.owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    elsif asset.upload_container
      case asset.upload_container
      when MemexProject
        return asset.upload_container.owner
      when User
        return current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end

    # Likely a public legacy asset
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
