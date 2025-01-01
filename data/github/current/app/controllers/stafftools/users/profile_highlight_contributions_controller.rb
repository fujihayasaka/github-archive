# typed: true
# frozen_string_literal: true

class Stafftools::Users::ProfileHighlightContributionsController < StafftoolsController
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
    only: [:index], optional: true

  def index
    profile_highlight_contributions_view =
      Stafftools::User::ProfileHighlightContributionsView.new(user: this_user)

    render(
      "stafftools/users/profile_highlight_contributions/index",
      locals: { view: profile_highlight_contributions_view },
    )
  end

  def update
    contribution = ProfileHighlightContribution.find_by(id: params[:id])

    if contribution
      contribution.update(ignore: !contribution.ignore)
      adjective = contribution.ignore ? "flagged" : "unflagged"
      flash[:notice] = "Contribution has been #{adjective} for ignore."

      redirect_to stafftools_user_profile_highlight_contributions_path(this_user)
    else
      render_404
    end
  end
end
