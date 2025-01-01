# typed: true
# frozen_string_literal: true

module Codespaces
  class RepositoryCodespacesController < AbstractRepositoryController
    include ApplicationController::CodespaceTagActionDependency
    include ControllerMethods::Codespaces

    before_action :login_required_redirect_for_public_repo
    before_action :redirect_without_feature
    before_action :redirect_on_empty_repo
    javascript_bundle :codespaces
    javascript_bundle :"code-menu"
    javascript_bundle :"codespaces-branch-selector"
    stylesheet_bundle :codespaces

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Spokes,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Configurations,
      ApplicationRecord::Ballast,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Memex,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      ApplicationRecord::Iam,
      only: [:allow_permissions]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Spokes,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:code_menu_contents]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :code_menu_contents, :allow_permissions], optional: true

    def index
      respond_to do |format|
        format.html do
          render "codespaces/repository_codespaces/index", locals: {
            query: query_for_dashboard,
            repository: current_repository,
            user_settings: Codespaces::Settings.for_user(current_user)
          }
        end
      end
    end

    def allow_permissions # rubocop:todo GitHub/UseRestfulActions
      devcontainer_path = params[:devcontainer_path].presence
      ref = params[:ref] || current_repository.default_branch
      oid = Codespaces::GetTargetRef.call(repository: current_repository, name_or_oid: ref)&.target_oid

      unless oid
        flash[:error] = "Invalid ref '#{ref}' for repository '#{current_repository.name_with_display_owner}'."
        return redirect_to repository_codespaces_path(current_repository)
      end

      devcontainer = Codespaces::DevContainer.new(
        repository: current_repository,
        oid: oid,
        filepath: devcontainer_path,
        user: current_user
      )

      begin
        permissions_diff = devcontainer.diff_all_permissions
      rescue Codespaces::DevContainer::ReadError => e
        flash[:error] = e.message
        return redirect_to repository_codespaces_path(current_repository)
      end

      if permissions_diff.any_permissions?
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        repo_readable_by_user_count = Repository.where(id: current_user.associated_repository_ids(organization: current_repository.owner, min_action: :read)).size
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      end

      if devcontainer.permissions_need_allowance?
        render "codespaces/repository_codespaces/allow_permissions", locals: {
            ref: params[:ref],
            devcontainer: devcontainer,
            repo_readable_by_user_count: repo_readable_by_user_count,
            devcontainer_path: params[:devcontainer_path],
          }, formats: :html
      else
        render "codespaces/repository_codespaces/add_consented_permissions", locals: {
            repository: current_repository
          }, formats: :html
      end
    end

    def add_consented_permissions # rubocop:todo GitHub/UseRestfulActions
      devcontainer_path = params[:devcontainer_path].presence
      error_message = nil
      begin
        Codespaces::WriteAllowedPermissions.call(
          user: current_user,
          repository: current_repository,
          ref: params[:ref],
          devcontainer_path: devcontainer_path,
          owner_permissions: params[:owner_permissions],
          repository_permissions: params[:repository_permissions],
          category: "api"
        )
      rescue ActiveModel::ValidationError => e
        GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:cli", "error_type:#{e.class.name}"])
        error_message = "Could not authorize requested permissions: #{e.model.errors.full_messages.to_sentence}"
      rescue Codespaces::Error => e
        GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:cli", "error_type:#{e.class.name}"])
        error_message = e.message
      end

      if error_message
        flash[:error] = error_message
        redirect_to repository_codespaces_path(current_repository)
      else
        render "codespaces/repository_codespaces/add_consented_permissions", locals: {
            repository: current_repository
          }, formats: :html
      end
    end

    def code_menu_contents # rubocop:todo GitHub/UseRestfulActions
      render Codespaces::CodeMenuCodespacesListComponent.new(
        visibility: codespaces_menu_visibility,
        ref: current_ref,
        repository: current_repository,
        name_param: params[:name],
        pull_request: current_pull_request,
      ), layout: false
    end

    private

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

      Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync.billable_owner || :no_target_for_conditional_access # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
    end

    # overriding resource for conditional access from app/controllers/repository_controller_methods.rb
    def resource_for_conditional_access
      # defaulting to `target_for_conditional_access` when user is logged in
      return self if logged_in?
      # fallback to app/controllers/repository_controller_methods.rb
      super
    end

    def current_pull_request
      return nil unless params[:pull_request].present?
      current_repository.issues.find_by_number(params[:pull_request].to_i).try(:pull_request)
    end

    def query_for_dashboard
      query = Codespaces::Query.new(
        current_user: current_user,
        repository: current_repository,
        ref: current_repository.default_branch,
        cap_filter: cap_filter
      )
      Codespace.prefill_associations_for_dashboard(query.codespaces)
      query
    end

    def redirect_without_feature
      unless current_user&.codespaces_feature_enabled?
        redirect_to "/features/codespaces", notice: "You don't have access to Codespaces yet. Sign up for the beta to get access."
        nil
      end
    end

    def redirect_on_empty_repo
      if current_repository.empty?
        flash[:error] = "Codespaces aren't available for empty repositories"
        redirect_to repository_path(current_repository)
      end
    end
  end
end
