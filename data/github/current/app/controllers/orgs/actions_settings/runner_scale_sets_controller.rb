# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RunnerScaleSetsController < Orgs::Controller
  include Actions::RunnersHelper

  before_action :login_required
  before_action :ensure_user_has_runners_and_runner_groups_access
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    scale_set_id = params[:id]&.to_i
    scale_set = Actions::RunnerScaleSet.get(current_organization, id: scale_set_id)

    return render_404 unless scale_set

    render "settings/organization/actions/runner_scale_set",
      locals: {
        scale_set: scale_set,
        owner_settings: Actions::OrgRunnersView.new({
          settings_owner: current_organization,
          current_user: current_user
        }),
      }
  end
end
