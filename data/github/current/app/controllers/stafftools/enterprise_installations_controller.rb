# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallationsController < StafftoolsController
  layout "layouts/stafftools/enterprise_installation"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
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

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index, :show], optional: true

  def index
    installations = EnterpriseInstallation
      .for_query(params[:query])
      .order("created_at desc")
      .paginate(page: params[:page])
    render "stafftools/enterprise_installations/index",
      layout: "stafftools", locals: { installations: installations }
  end

  def show
    render "stafftools/enterprise_installations/show",
      locals: { installation: this_enterprise_installation }
  end

  def destroy
    this_enterprise_installation.destroy
    redirect_to \
      stafftools_enterprise_installations_path,
      notice: "Enterprise Server installation removed."
  end
end
