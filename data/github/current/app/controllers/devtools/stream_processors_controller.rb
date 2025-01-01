# typed: true
# frozen_string_literal: true

class Devtools::StreamProcessorsController < DevtoolsController

  before_action :ensure_group_id_is_present, only: [:pause, :resume]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    ::GitHub::StreamProcessors::SimpleProcessor if Rails.env.development? # Load simple processor so we have something in development

    processor_classes = ::GitHub::StreamProcessors::BaseProcessor.descendants.select { |klass| klass.subclasses.empty? }
    processors, unknown_group_id_processors = processor_classes.map(&:new).partition(&:group_id)

    paused_processors, running_processors = processors.partition(&:paused?)

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "Hydro Stream Processors",
      path: devtools_stream_processors_path,
      parent: ContextRegion::DevtoolsCrumb.new
    )

    render "devtools/stream_processors/index", locals: {
      stream_processors_class: ::GitHub::StreamProcessors::BaseProcessor,
      paused_processors: paused_processors.sort_by { |p| [p.paused_at, p.class.name] },
      running_processors: running_processors.sort_by { |p| p.class.name },
      unknown_group_id_processors: unknown_group_id_processors.sort_by { |p| p.class.name }
    }
  end

  def pause # rubocop:todo GitHub/UseRestfulActions
    ::GitHub::StreamProcessors::BaseProcessor.pause(
      params[:stream_processor_group_id],
      raise_immediately: false,
      reason: "Manually paused in devtools by #{current_user.login}"
    )

    redirect_to devtools_stream_processors_path, notice: "Stream processor #{params[:stream_processor_group_id]} paused!"
  end

  def resume # rubocop:todo GitHub/UseRestfulActions
    ::GitHub::StreamProcessors::BaseProcessor.resume(params[:stream_processor_group_id])

    redirect_to devtools_stream_processors_path, notice: "Stream processor #{params[:stream_processor_group_id]} resumed!"
  end

  private

  # Compares the paused at times for the stream processors
  # Since resumed processors will have this value set to nil and
  # we can't compare nil to time we set nil values to the bottom
  def compare_paused_at(paused_at_a, paused_at_b)
    if paused_at_a && paused_at_b
      paused_at_a <=> paused_at_b
    elsif paused_at_a
      -1
    else
      1
    end
  end

  def ensure_group_id_is_present
    if params[:stream_processor_group_id].blank?
      redirect_to devtools_stream_processors_path, alert: "Processor Group ID is required"
    end
  end
end
