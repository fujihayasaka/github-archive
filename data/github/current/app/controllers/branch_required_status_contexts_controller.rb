# typed: true
# frozen_string_literal: true

class BranchRequiredStatusContextsController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_user_has_edit_branch_protection
  before_action :set_protected_branch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:suggestions]

  def show
    return head 404 if params[:item].blank?

    context = params[:item]

    integrations_by_context = @protected_branch.possible_required_status_contexts_and_integrations

    return head 404 unless integrations_by_context.has_key?(context)
    selected_integration = integrations_by_context[context].first

    respond_to do |format|
      format.html do
        render partial: "branch_required_status_contexts/context", locals: {
          context: context,
          protected_branch: @protected_branch,
          selected_integration: selected_integration,
        }
      end
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    query = params[:q].downcase

    suggestions = @protected_branch.possible_required_status_contexts_and_integrations.keys
      .select { |status_context| status_context.downcase.include?(query) }
      .sort

    respond_to do |format|
      format.html_fragment do
        render partial: "branch_required_status_contexts/suggestions", formats: :html, locals: {
          suggestions: suggestions
        }
      end
      format.html do
        render partial: "branch_required_status_contexts/suggestions", locals: {
          suggestions: suggestions
        }
      end
    end
  end

  private

  def set_protected_branch
    if params[:branch].present?
      @protected_branch = current_repository.protected_branches.find_by(name: params[:branch])
    end

    @protected_branch ||= current_repository.protected_branches.new
  end

  def ensure_user_has_edit_branch_protection
    render_404 unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end
end
