# typed: true
# frozen_string_literal: true

class Issue::Loader::Projects < Issue::Loader::Base
  def initialize(context, project_ids: [])
    @context = context
    @project_ids = project_ids
  end

  def self.load_for(context, project_ids: [])
    super new(context, project_ids: project_ids)
  end

  def self.preload_for(context, projects: [])
    new(context).preload(projects)
  end

  def load
    return {} unless @project_ids.any?

    Project.strict_loading.
      where(id: @project_ids).
      index_by(&:id)
  end

  def preload(projects)
    return unless projects.any?
    track_execution_time do
      Promise.all([
        async_preload_attribute(projects, :url, :async_url),
      ]).sync
    end
  end
end
