# typed: true
# frozen_string_literal: true

module Ability::ProjectDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Ability))
    scope :teams_direct_on_projects, ->(project_id:) {
      direct.where({
        actor_type: "Team",
        subject_type: "Project",
        subject_id: project_id,
      })
    }
  end
end
