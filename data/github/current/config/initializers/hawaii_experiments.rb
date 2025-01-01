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
      "dashboard_onboarding_copilot_free_vs_none",
      "dashboard_copilot_agent_mode_launch_nudge",
      "dashboard_copilot_agent_mode_launch_nudge_step_2",
      "dashboard_copilot_agent_mode_launch_nudge_step_3",
      "dfd_show_new_tasks_nudges",
    ]).freeze,
    T::Set[String]
  )

  # Raise error if duplicate IDs are attempted to be added
  sig { params(id: String).void }
  def self.add_experiment(id)
    HAWAII_EXPERIMENT_IDS.add(id)
  end
end
