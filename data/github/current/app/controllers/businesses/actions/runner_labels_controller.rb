# typed: true
# frozen_string_literal: true

class Businesses::Actions::RunnerLabelsController < Businesses::BusinessController

  include ::Actions::RunnersHelper

  before_action :login_required
  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    respond_to do |format|
      format.html do
        render(Actions::RunnerLabelsComponent.new(
          owner: this_business,
          runner_ids: params[:runner_id].present? ? [params[:runner_id]] : [],
          labels: labels_for(this_business, is_ui_read: true),
          selected_labels: params[:applied_labels],
          form_id: params[:form_id]
        ), layout: false)
      end
    end
  end

  def create
    label = create_label_for(this_business, name: params[:name])

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
    affected_runner, destination = update_label_for(this_business, runner_id: params[:runner_id].to_i, labels: labels)

    unless affected_runner.present?
      flash[:error] = "Sorry, there was a problem updating your labels"
    end

    owner_settings = Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user)

    redirect_to settings_actions_update_runner_enterprise_path(id: params[:runner_id], written_to: destination)
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end
end
