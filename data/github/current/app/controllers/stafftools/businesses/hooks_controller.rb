# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::HooksController < Stafftools::Businesses::BusinessBaseController
  before_action :hook_view, only: %i(show)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    # Need to load the last status for hooks to list
    hooks = Hook::StatusLoader.load_statuses \
      hook_records: this_business.hooks.ordered.all, parent: this_business
    render "stafftools/businesses/hooks", locals: { business: this_business, hooks: hooks }
  end

  def show
    render "stafftools/hooks/show", locals: { hook_deliveries_query: params[:deliveries_q] }
  end

  private

  memoize def hook_view
    @hook_view = Hooks::ShowView.new hook: this_hook
  end

  memoize def this_hook
    @hook = this_business.hooks.find(params[:id])
  end

  # Required as a helper method by the shared hooks views.
  # See app/views/stafftools/hooks/show.html.erb.
  def current_context
    this_business
  end
  helper_method :current_context
end
