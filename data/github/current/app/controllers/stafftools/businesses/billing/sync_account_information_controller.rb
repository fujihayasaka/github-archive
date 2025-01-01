# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::SyncAccountInformationController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    return render_404 unless this_business.eligible_for_self_serve_payment?
    return render_404 if this_business.trial?

    render "stafftools/businesses/billing/sync_account_information/show", locals: {
      business: this_business
    }, layout: false
  end

  def update
    return render_404 unless this_business.eligible_for_self_serve_payment?
    return render_404 if this_business.trial?

    Billing::SynchronizeAccountInformationJob.perform_later(this_business)
    flash[:notice] = "Account information sychronization enqueued."

    redirect_to :back
  end
end
