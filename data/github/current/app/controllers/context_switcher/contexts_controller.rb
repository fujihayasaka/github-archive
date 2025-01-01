# typed: true
# frozen_string_literal: true

module ContextSwitcher
  class ContextsController < ApplicationController
    before_action :login_required
    before_action :non_emu_required
    before_action :dotcom_required
    before_action :require_redirect_paths, only: [:index]
    before_action :check_current_context_is_in_user_list, only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      optional: true

    def index
      respond_to do |format|
        format.html do
          render ContextSwitcher::ListComponent.new(
            contexts: contexts,
            current_context: current_context,
            redirect_paths:  redirect_paths,
          ), layout: false
        end
      end
    end

    private

    def require_redirect_paths
      render_404 unless params.key?(:redirect_paths)
    end

    def check_current_context_is_in_user_list
      render_404 unless current_user && contexts.any? { |context| context.account == current_context }
    end

    def redirect_paths
      params[:redirect_paths].permit(:org, :user)
    end

    def target_for_conditional_access
      # Target = User in this case, since we're aiming to return a list of User or Organization links
      # that the current user owns or is a member of. This has been previously filtered by the User
      # DashboardContext.
      #
      # current_context = The currently selected User/Organization, which will show up on the list as
      # checked. If current_context does not exist in this list, the controller will 404.
      #
      # Since CAP runs before other filters like login_required and current_user may be logged_out, we
      # need this bypass to account for this case.
      return :no_target_for_conditional_access unless logged_in? # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    memoize def contexts
      contexts = current_user.dashboard_contexts.contexts
      if params[:show_only_owning] == "true"
        contexts = contexts.select { |context| context.adminable }
      end
      contexts
    end

    memoize def current_context
      User.find_by(login: params[:current_context])
    end
  end
end
