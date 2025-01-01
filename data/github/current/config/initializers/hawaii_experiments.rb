# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "set"

module HawaiiExperiments
  extend ActiveSupport::Concern

  # Store hawaii A|B test experiment IDs in a Set to ensure uniqueness
  HAWAII_EXPERIMENT_IDS = T.let(
    T::Set[String].new([
      #add experiment IDs here
      "discover_more_projects_with_copilot",
      "dashboard_copilot_extensions_docker_simple_vs_value",
      "dashboard_2025_03_27_roadmap_mario_vs_copilot",
    ]).freeze,
    T::Set[String]
  )

  # Raise error if duplicate IDs are attempted to be added
  sig { params(id: String).void }
  def self.add_experiment(id)
    HAWAII_EXPERIMENT_IDS.add(id)
  end
end
