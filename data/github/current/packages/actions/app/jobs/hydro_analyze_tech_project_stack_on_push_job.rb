# typed: true
# frozen_string_literal: true

class HydroAnalyzeTechProjectStackOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_analyze_tech_project_stack_on_push

  def perform
    return unless push_includes_default_branch?
    TechProjectStackAnalysis.enqueue_analyze_tech_project_stack(repository.id)
  end
end
