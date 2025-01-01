# typed: strict
# frozen_string_literal: true


class Stafftools::Users::TradeCompliance::CheckViolationsController < Stafftools::Users::TradeComplianceController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Ballast,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Billing,
  ApplicationRecord::Repositories,
  ApplicationRecord::IssuesPullRequests,
  only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:show],
  optional: true

  sig { void }
  def show
    return render_404 unless request.xhr?

    checker = TradeControls::ComplianceChecksDryRun.new(target)
    checker.run

    render json: { violations: checker.humanize_violations }
  end
end
