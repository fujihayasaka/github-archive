# typed: true
# frozen_string_literal: true

class EditRepositories::PullRequestCreationPolicyController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required

  def update
    restricted_to_collaborators = params[:pull_request_creation_policy] == "collaborators_only"
    update_success = false
    begin
      PullRequestCreationConfig.new(current_repository).set_pull_request_creation_policy(
        policy: restricted_to_collaborators ? Configurable::PullRequestCreationPolicy::COLLABORATORS_ONLY : Configurable::PullRequestCreationPolicy::ALL,
        actor: current_user
      )
      update_success = true
    rescue ArgumentError
      update_success = false
    end

    respond_to do |format|
      format.turbo_stream do
        render "edit_repositories/pull_request_creation_policy/update", locals: { update_success: update_success }
      end

      format.html do
        if request.xhr?
          head :ok
        else
          redirect_to :back
        end
      end

      format.all do
        head :ok
      end
    end
  end
end
