# typed: true
# frozen_string_literal: true

class Stafftools::RetiredNamespacesController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 25

  def index
    retired_namespaces = RetiredNamespace.order(owner_login: :asc, name: :asc).paginate(
      page: current_page,
      per_page: PER_PAGE,
    )

    render "stafftools/retired_namespaces/index", locals: { retired_namespaces: retired_namespaces }
  end

  def destroy
    retired_namespace = RetiredNamespace.find_by(id: params[:id])
    return render_404 unless retired_namespace.present?

    result = retired_namespace.unretire

    if result.success?
      flash[:notice] = "Unretired #{retired_namespace.name_with_owner}"
    else
      flash[:error] = "Unretiring namespace failed: #{result.errors.to_sentence}"
    end

    redirect_to stafftools_retired_namespaces_path
  end
end
