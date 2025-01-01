# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::SyncSubscriptionController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    return render_404 unless this_business.eligible_for_self_serve_payment?
    return render_404 if this_business.trial?

    render "stafftools/businesses/billing/sync_subscription/show", locals: {
      business: this_business
    }, layout: false
  end

  def update
    return render_404 unless this_business.eligible_for_self_serve_payment?
    return render_404 if this_business.trial?

    this_business.create_or_update_external_subscription!(force: true)
    flash[:notice] = "External subscription sychronization enqueued."

    redirect_to :back
  end
end
