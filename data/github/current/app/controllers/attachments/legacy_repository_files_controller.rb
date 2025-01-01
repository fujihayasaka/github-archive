# typed: true
# frozen_string_literal: true

class Attachments::LegacyRepositoryFilesController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    if FeatureFlag.vexi.enabled?(:allow_header_auth_for_repository_files, default: true)
      return render_404 unless repository_file
      return render_404 if repository_file.using_new_url?
      repository_file.download
      redirect_to repository_file.redirect_url(actor: current_user)
    else
      file = RepositoryFile.where(
        id: params[:id],
        name: params[:path],
        repository_id: current_repository.id,
        state: 1, # uploaded
      ).first
      return render_404 unless file
      return render_404 if file.using_new_url?
      file.download
      redirect_to file.redirect_url(actor: current_user)
    end
  end

  protected

  # Override ApplicationController#authentication_methods to accept
  # an alternative auth method. The alternative auth method lets us
  # authenticate a session-less logged in request for assets while
  # using clients like GitHub Desktop etc.
  def authentication_methods
    return super unless FeatureFlag.vexi.enabled?(:allow_header_auth_for_repository_files, default: true) && header_auth_allowed?

    super || login_from_authorization_header_auth
  end

  private

  memoize def repository_file
    if FeatureFlag.vexi.enabled?(:allow_header_auth_for_repository_files, default: true)
      RepositoryFile.where(
        id: params[:id],
        name: params[:path],
        repository_id: current_repository.id,
        state: 1, # uploaded
      ).first
    end
  end

  # Copied from `UserAssetsController`. Safe, since we only allow Oauth access
  # for files associated with a repository
  def adequate_oauth_scope(scopes)
    Api::AccessControl.oauth_allows_access?(current_user, current_repository) if FeatureFlag.vexi.enabled?(:allow_header_auth_for_repository_files, default: true) && repository_file
  end

  # Determines whether header authentication is allowed for the current action.
  def header_auth_allowed?
    %w{show}.include?(action_name)
  end
end
