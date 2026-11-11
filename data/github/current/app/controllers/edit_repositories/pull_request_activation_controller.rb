# typed: true
# frozen_string_literal: true

class EditRepositories::PullRequestActivationController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :add_spamurai_form_signals, only: [:update]

  def update
    pull_request_activation_config = PullRequestActivationConfig.new(current_repository)
    if params[:has_pull_requests] == "1"
      pull_request_activation_config.enable_pull_requests(actor: current_user)
    else
      pull_request_activation_config.disable_pull_requests(actor: current_user)
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          update_react_global_navigation_tabs

          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :repo_settings,
            display_variant: :none,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        else
          head :ok
        end
      end

      format.all do
        head :ok
      end
    end
  end
end
