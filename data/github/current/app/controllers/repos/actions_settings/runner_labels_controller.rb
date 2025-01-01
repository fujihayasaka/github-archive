# typed: true
# frozen_string_literal: true

class Repos::ActionsSettings::RunnerLabelsController < AbstractRepositoryController
  include Actions::RunnersHelper

  before_action :login_required
  before_action :ensure_actions_runners_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    respond_to do |format|
      format.html do
        render(Actions::RunnerLabelsComponent.new(
          owner: current_repository,
          runner_ids: params[:runner_id].present? ? [params[:runner_id]] : [],
          labels: labels_for(current_repository, is_ui_read: true),
          selected_labels: params[:applied_labels],
          form_id: params[:form_id]
        ), layout: false)
      end
    end
  end

  def create
    label = create_label_for(current_repository, name: params[:name])

    respond_to do |wants|
      wants.html do
        if label
          render(Actions::RunnerLabelComponent.new(label: label, selected: false), layout: false)
        else
          errorMessage = "Sorry, there was a problem adding your label."
          render json: { message: errorMessage }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    labels = Array(params[:labels])
    affected_runner, destination = update_label_for(current_repository, runner_id: params[:runner_id].to_i, labels: labels)

    unless affected_runner.present?
      flash[:error] = "Sorry, there was a problem updating your labels"
    end
    flash[:notice] = "Runner labels succesfully updated"
    redirect_to repository_actions_settings_runner_details_path(id: params[:runner_id], written_to: destination)
  end
end
