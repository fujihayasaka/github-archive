# typed: true
# frozen_string_literal: true

class Businesses::Actions::RunnerScaleSetsController < Businesses::BusinessController
  include Actions::RunnersHelper

  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :business_not_downgraded_to_free_plan_required

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    scale_set_id = params[:id]&.to_i
    scale_set = Actions::RunnerScaleSet.get(this_business, id: scale_set_id)

    return render_404 unless scale_set

    render "businesses/settings/actions/runner_scale_set",
      locals: {
        scale_set: scale_set,
        owner_settings: Actions::EnterpriseRunnersView.new({
          settings_owner: this_business,
          current_user: current_user
        }),
      }
  end
end
