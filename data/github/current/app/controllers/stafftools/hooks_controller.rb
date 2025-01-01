# typed: true
# frozen_string_literal: true

class Stafftools::HooksController < StafftoolsController

  before_action :context_required
  before_action :ensure_user_exists
  before_action :hook_view, only: [:show, :toggle_active_status]

  helper_method :current_context, :repo_hooks?

  layout :new_nav_layout
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index], optional: true

  private def new_nav_layout
    if repo_hooks?
      "layouts/stafftools/repository/security"
    else
      "layouts/stafftools/organization/security"
    end
  end

  def index
    # TODO: MV this helper once the stafftools view model PR gets merged
    @hooks_view = Stafftools::RepositoryViews::HooksView.new(current_context: current_context)
    render "stafftools/hooks/index"
  end

  def show
    render "stafftools/hooks/show", locals: { hook_deliveries_query: params[:deliveries_q] }
  end

  def toggle_active_status # rubocop:todo GitHub/UseRestfulActions
    hook.toggle_active_status_from_stafftools(disable_reason: params[:disable_reason])
    flash[:notice] = "Okay, the webhook was successfully #{hook_view.hook_active_status}."
    redirect_to :back
  end

  private

  def hook_view
    @hook_view = Hooks::ShowView.new hook: hook
  end

  def hook # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @hook ||= begin
      if current_context.is_a?(Repository) && current_context.repo_hook_associations_ff?
        Hook.hooks_for_target(current_context).find(params[:id])
      else
        current_context.hooks.find(params[:id])
      end
    end
  end

  def current_context
    if repo_hooks?
      current_repository
    else
      # user needed for Stafftools user layout
      this_user || Organization.find_by_login(params[:user])
    end
  end

  def context_required
    raise NotFound unless current_context
  end

  def repo_hooks?
    params[:repository].present?
  end
end
