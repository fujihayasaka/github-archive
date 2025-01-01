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
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    experiment = ::Experiment.find_by!(name: params[:experiment_id])

    page = params.fetch(:page) { 1 }
    page = page.to_i

    mismatches = experiment.mismatches(page: page)
    mismatches = mismatches.map do |mismatch|
      Devtools::Experiments::MismatchView.new experiment_data: mismatch
    end
    render "devtools/mismatches/index", locals: {
      mismatches: mismatches,
      experiment: experiment,
      page: page,
    }
  end
end
