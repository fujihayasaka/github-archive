# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::UserNamespaceRepositoriesController < Stafftools::Businesses::BusinessBaseController
  before_action :enterprise_managed_business_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    user_namespace_repositories = this_business.user_namespace_repositories(query: params[:query])
    return render_404 if user_namespace_repositories.nil?

    repositories = user_namespace_repositories.order("repositories.owner_login ASC")
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "stafftools/businesses/user_namespace_repositories_list", locals: {
            query: params[:query],
            repositories: repositories,
          }
        else
          render "stafftools/businesses/user_namespace_repositories", locals: {
            query: params[:query],
            repositories: repositories,
          }
        end
      end
    end
  end
end
