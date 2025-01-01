# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RunnerLabelsController < Orgs::Controller
  include Actions::RunnersHelper

  before_action :login_required
  before_action :ensure_user_has_runners_and_runner_groups_access
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
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
    respond_to do |format|
      format.html do
        render(Actions::RunnerLabelsComponent.new(
          owner: current_organization,
          runner_ids: params[:runner_id].present? ? [params[:runner_id]] : [],
          labels: labels_for(current_organization),
          selected_labels: params[:applied_labels],
          form_id: params[:form_id]
        ), layout: false)
      end
    end
  end

  def create
    label = create_label_for(current_organization, name: params[:name])

    respond_to do |wants|
      wants.html do
        if label
          render(Actions::RunnerLabelComponent.new(label: label, selected: false, form_id: params[:form_id]), layout: false)
        else
          errorMessage = "Sorry, there was a problem adding your label."
          render json: { message: errorMessage }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    labels = Array(params[:labels])
    affected_runner = update_label_for(current_organization, runner_id: params[:runner_id], labels: labels)

    unless affected_runner
      flash[:error] = "Sorry, there was a problem updating your labels"
    end

    # Runner groups are enabled, so we re-render the runner component only, instead of the entire containing box.
    # This avoids expanded runner groups from closing themselves.
    owner_settings = Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user)

    redirect_to settings_org_actions_update_runner_path(id: params[:runner_id])
  end
end
