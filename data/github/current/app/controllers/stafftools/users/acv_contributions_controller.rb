# typed: true
# frozen_string_literal: true

class Stafftools::Users::AcvContributionsController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_user_not_org

  layout "layouts/stafftools/user/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    acv_contributions_view = Stafftools::User::AcvContributionsView.new(user: this_user)

    render "stafftools/users/acv_contributions/index", locals: { view: acv_contributions_view }
  end

  def update
    contribution = AcvContributor.find_by(id: params[:id])

    if contribution
      contribution.update(ignore: !contribution.ignore)
      adjective = contribution.ignore ? "flagged" : "unflagged"
      flash[:notice] = "Contribution has been #{adjective} for ignore."

      redirect_to stafftools_user_acv_contributions_path(this_user)
    else
      render_404
    end
  end
end
