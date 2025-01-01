# typed: true
# frozen_string_literal: true
class MoveWork::OrganizationsController < MoveWork::BaseController
  javascript_bundle "pricing"
  javascript_bundle "billing"
  stylesheet_bundle "pricing"
  stylesheet_bundle "site"

  before_action :require_choose_resources_step_completed

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:plans]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:plans], optional: true

  def plans # rubocop:todo GitHub/UseRestfulActions
    render "move_work/organizations/plans", locals: {
      progressbar_value: 20,
    }
  end

  private

  def require_choose_resources_step_completed
    redirect_to new_move_work_path(current_context) unless move_work_session["repository_ids"]
  end
end
