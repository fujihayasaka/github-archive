# typed: true
# frozen_string_literal: true

class RepositoryDeploymentsController < AbstractRepositoryController
  map_to_service :deployments # rubocop:todo GitHub/MapToService
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::ActionsEnvironments

  depends_on_clusters ApplicationRecord::Copilot, only: [
    :deployments,
    :environment_deployments
  ], optional: true


  # add to make requests from react apps using verifiedFetch
  include ApplicationController::VerifiedFetchDependency

  include DeploymentsHelper

  self.react_bundle_name = "repo-deployments"

  def deployments # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.can_see_deployments?(current_user)

    render_react_app(
      page_data: {
        selected_link: :repo_deployments
      },
      app_payload_generator: -> { app_payload },
      title: "Deployments · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository_with_container",
    )
  end

  # TODO: Environments are not encoded in the params this causes issues
  # when rendering the environment status
  def environment_deployments # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.can_see_deployments?(current_user)
    return render_404 unless current_repository.environments.where(name: params[:environment]).exists?

    render_react_app(
      page_data: {
        selected_link: :repo_deployments
      },
      app_payload_generator: -> { app_payload },
      title: "Deployments · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository_with_container",
    )
  end

  # TODO: Clean this up once we deprecate the old deployments experience
  def deployments_activity_log # rubocop:todo GitHub/UseRestfulActions
    unless params[:environment].present?
      return redirect_to deployments_path
    end
    redirect_to environment_deployments_path(environment: params[:environment])
  end

  private

  def app_payload
    user = current_user || User.ghost
    {
      canManagePinning: current_repository.can_pin_environments?(current_user),
      currentUser: {
        login: user.display_login,
        name: user.name,
        avatarUrl: user.primary_avatar_url(80),
      }
    }
  end

end
