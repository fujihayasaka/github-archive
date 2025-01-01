# typed: true
# frozen_string_literal: true

class Devtools::ExperimentsController < DevtoolsController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new],
    optional: true

  def index
    active, inactive = ::Experiment.order(:name).partition(&:active?)
    display_active = !!(params[:active] == "true" || params[:active].blank?)
    if display_active
      experiments = active
    else
      experiments = inactive
    end
    render "devtools/experiments/index", locals: { experiments: experiments, active: display_active }
  end

  def new
    render "devtools/experiments/new", locals: {
      experiment: ::Experiment.new,
    }
  end

  def create
    experiment = ::Experiment.new(experiment_params)

    if experiment.save
      redirect_to devtools_experiment_path(experiment), notice: "'#{experiment.name}' has been created"
    else
      flash.now[:error] = "Error creating the experiment"
      render "devtools/experiments/new", locals: {
        experiment: ::Experiment.new,
      }
    end
  end

  def show
    experiment = find_experiment

    render "devtools/experiments/show",
      locals: {
        experiment: experiment,
        datadog_dashboard_link: datadog_dashboard_link(experiment),
        sentry_link: sentry_link(experiment),
        sentry_timeout_link: sentry_timeout_link(experiment),
      }
  end

  def update
    experiment = find_experiment

    unless experiment.update(experiment_params)
      flash.now[:error] = "Error updating the experiment"
    end
    render "devtools/experiments/show",
      locals: {
        experiment: experiment,
        datadog_dashboard_link: datadog_dashboard_link(experiment),
        sentry_link: sentry_link(experiment),
        sentry_timeout_link: sentry_timeout_link(experiment),
      }
  end

  def update_sample # rubocop:todo GitHub/UseRestfulActions
    experiment = find_experiment
    threshold = sample_params[:threshold].to_i
    duration = sample_params[:duration].to_i

    if threshold.positive?
      experiment.set_sample_threshold threshold, duration
      flash.now[:notice] = "Sampling has been enabled"
    else
      flash.now[:error] = "Sample threshold must be greater than 0"
    end
    render "devtools/experiments/show",
      locals: {
        experiment: experiment,
        datadog_dashboard_link: datadog_dashboard_link(experiment),
        sentry_link: sentry_link(experiment),
        sentry_timeout_link: sentry_timeout_link(experiment),
      }
  end

  def disable_sample # rubocop:todo GitHub/UseRestfulActions
    experiment = find_experiment

    experiment.disable_sampling
    if !experiment.currently_sampling?
      flash.now[:notice] = "Sampling has been disabled"
    else
      flash.now[:error] = "Could not disable sampling"
    end
    render "devtools/experiments/show",
      locals: {
        experiment: experiment,
        datadog_dashboard_link: datadog_dashboard_link(experiment),
        sentry_link: sentry_link(experiment),
        sentry_timeout_link: sentry_timeout_link(experiment),
      }
  end

  def clear # rubocop:todo GitHub/UseRestfulActions
    experiment = find_experiment
    flash[:notice] = "Mismatches from this experiment will be cleared shortly"

    Experiments::ClearMismatchesJob.perform_later(experiment)
    redirect_back fallback_location: devtools_experiment_path(experiment)
  end

  def destroy
    experiment = find_experiment

    Experiments::DestroyJob.perform_later(experiment)
    redirect_to devtools_experiments_path, notice: "Experiment will be deleted shortly"
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    experiment = ::Experiment.find_by(name: params[:id])

    if experiment
      set_nav_breadcrumb ContextRegion::Devtools::ExperimentCrumb.new(experiment)
    else
      set_nav_breadcrumb ContextRegion::Devtools::ExperimentsIndexCrumb.new
    end
  end

  def find_experiment
    ::Experiment.find_by!(name: params[:id])
  end

  def experiment_params
    params.require(:experiment).permit(:name, :percent)
  end

  def sample_params
    params.require(:sample).permit(:threshold, :duration)
  end

  def datadog_dashboard_link(experiment)
    url = safe_join(["https://app.datadoghq.com/dash/359818/scienceexperiments?live=true&tpl_var_experiment=", experiment.name])
    ActionController::Base.helpers.link_to("Datadog Dashboard", url, target: "_blank", rel: "noopener noreferrer")
  end

  def sentry_link(experiment)
    url = safe_join(["https://sentry.io/organizations/github/issues/?project=1885898&query=gh.scientist.experiment%3A", experiment.name])
    ActionController::Base.helpers.link_to("github", url, target: "_blank", rel: "noopener noreferrer")
  end

  def sentry_timeout_link(experiment)
    url = safe_join(["https://sentry.io/organizations/github/issues/?project=1885966&query=gh.scientist.experiment%3A", experiment.name])
    ActionController::Base.helpers.link_to("github-timeout", url, target: "_blank", rel: "noopener noreferrer")
  end
end
