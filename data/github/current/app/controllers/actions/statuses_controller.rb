# typed: true
# frozen_string_literal: true

class Actions::StatusesController < AbstractRepositoryController
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:index]

  param_encoding :index, :q, "ASCII-8BIT"

  def index
    statuses = [[:queued, :in_progress, :waiting, :completed].map { |status| status.to_s }, CheckRun.conclusions.keys.map { |status| status.to_s }].flatten
    is_lab = params[:lab] == "true"
    search_query = params[:q].to_s


    if !search_query.empty?
      statuses = statuses.select { |status| status.include?(search_query) }
    end

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render "actions/statuses/index",
          layout: false,
          formats: [:html, :html_fragment],
          locals: {
            selected_filename: params[:selected_filename],
            is_lab: is_lab,
            statuses: statuses,
            workflow_run_filters: workflow_run_filters,
          }
      end

      format.json do
        render json: statuses
      end
    end
  end
end
