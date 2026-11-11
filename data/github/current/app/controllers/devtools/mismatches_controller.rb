# typed: true
# frozen_string_literal: true

class Devtools::MismatchesController < DevtoolsController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  before_action :find_experiment

  def index
    page = params.fetch(:page) { 1 }
    page = page.to_i

    mismatches = @experiment.mismatches(page: page)
    mismatches = mismatches.map do |mismatch|
      Devtools::Experiments::MismatchView.new experiment_data: mismatch.parsed_payload, science_event: mismatch
    end
    render "devtools/mismatches/index", locals: {
      mismatches: mismatches,
      experiment: @experiment,
      page: page,
    }
  end

  def show
    science_event = ScienceEvent.find_by!(id: params[:id], name: @experiment.name)
    mismatch = Devtools::Experiments::MismatchView.new experiment_data: science_event.parsed_payload, science_event: science_event

    render "devtools/mismatches/show", locals: {
      mismatch: mismatch,
      experiment: @experiment,
    }
  end

  private

  def find_experiment
    @experiment = ::Experiment.find_by!(name: params[:experiment_id])
  end
end
