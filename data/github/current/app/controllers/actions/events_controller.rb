# typed: true
# frozen_string_literal: true

class Actions::EventsController < AbstractRepositoryController
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:index]

  param_encoding :index, :q, "ASCII-8BIT"

  def index
    events = find_all_events_by_elasticsearch(current_repository)
    is_lab = params[:lab] == "true"
    search_query = params[:q].to_s

    if !search_query.empty?
      events = events.select { |event| event.include?(search_query) }
    end

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render "actions/events/index",
          layout: false,
          formats: [:html, :html_fragment],
          locals: {
            selected_filename: params[:selected_filename],
            is_lab: is_lab,
            events: events,
            workflow_run_filters: workflow_run_filters
          }
      end

      format.json do
        render json: events
      end
    end
  end

  def find_all_events_by_elasticsearch(repo) # rubocop:todo GitHub/UseRestfulActions
    events = Actions::WorkflowRun.distinct_by(
      repo: current_repository,
      field: :event,
      size: 100, # There are 53 distinct webhook events today
    )

    all_events = events[:distinct_values]
    all_events.sort
  end
end
