# typed: true
# frozen_string_literal: true

class Devtools::SamplesController < DevtoolsController

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

    samples = experiment.samples(page: page)
    samples = samples.map do |sample|
      Devtools::Experiments::SampleView.new experiment_data: sample
    end
    render "devtools/samples/index", locals: {
      samples: samples,
      experiment: experiment,
      page: page,
    }
  end
end
