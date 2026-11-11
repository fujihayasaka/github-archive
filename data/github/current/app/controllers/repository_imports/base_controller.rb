# typed: false
# frozen_string_literal: true

module RepositoryImports

  # Internal: Repository import controllers all inherit from this controller.
  class BaseController < AbstractRepositoryController
    include OrganizationsHelper

    before_action :porter_available!
    before_action :porter_maintenance_mode!
    before_action :ensure_visible_to_user

    javascript_bundle :repositories

    rescue_from Porter::ApiClient::Error do |error|
      failbot(error)

      if Rails.env.development?
        raise error
      else
        render_porter_unavailable
      end
    end

    private

    # Internal: The repository import for this repository and user.
    #
    # Returns a RepositorySourceImport.
    def repository_import # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @repository_import ||= RepositorySourceImport.new(
        repository: current_repository,
        user: current_user,
      )
    end

    # Construct a RepositoryActionsSourceImport for this repository and user.
    #
    # @return [RepositoryActionsSourceImport] RepositoryActionsSourceImport instance for the repository and user.
    memoize def repository_actions_source_import
      RepositoryActionsSourceImport.new(
        repository: current_repository,
        user: current_user
      )
    end

    # Internal: Block access unless user is logged in, the repository imports
    # feature is enabled, and Porter is available.
    def porter_available!
      unless GitHub.porter_available?
        render_404
      end
    end

    # Internal: Block access if porter is in maintenance mode.
    def porter_maintenance_mode!
      render_porter_maintenance_mode if GitHub.porter_maintenance_mode?
    end

    # Internal: Render 404 if there is no current_repository.
    # Redirect back to the repository if user does not have push permission
    # or if the repository was never imported with Porter.
    def ensure_visible_to_user
      if current_repository.nil?
        render_404
      elsif !current_user_can_push?
        redirect_to repository_path(current_repository)
      end
    end

    # Internal: Render Porter unavailable view.
    def render_porter_unavailable
      render "repository_imports/porter_unavailable"
    end

    # Internal: Render Porter maintenance view.
    def render_porter_maintenance_mode
      render "repository_imports/porter_maintenance_mode"
    end

    # Subclass controllers all have user_id on the URL (except create, which uses owner)
    # So, there shouldn't be a case where CAP is bypassesed that doesn't 404.
    # However, if that isn't true, it'd be better to fail closed than open. So, we just
    # return target_repository_owner.
    def target_for_conditional_access
      target_repository_owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    def resource_for_conditional_access
      target_repository_owner || :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    end

    # NB: The `owner` helper method queries based on the :user_id param.
    #     We fall back to querying based on the :owner param for the
    #     POST #create endpoint, which accepts :owner as a request param but
    #     does not have a :user_id param in the URL, as in
    #     `/:user_id/:repository/import`.
    def target_repository_owner
      User.find_by_login(params[:owner] || params[:user_id])
    end
  end
end
