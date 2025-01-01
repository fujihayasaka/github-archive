# typed: true
# frozen_string_literal: true

module Ability::RepositoryDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Ability }

  included do
    T.bind(self, T.class_of(Ability))

    scope :user_direct_read_on_repository, ->(actor_id:, subject_id:) {
      direct.where({
        actor_id: actor_id,
        actor_type: "User",
        subject_id: subject_id,
        subject_type: "Repository",
      })
    }

    scope :user_direct_write_on_repository, ->(actor_id:, subject_id:) {
      direct_write.where({
        actor_id: actor_id,
        actor_type: "User",
        subject_id: subject_id,
        subject_type: "Repository",
      })
    }

    scope :teams_direct_on_repos, ->(repo_id:) {
      direct.where({
        actor_type: "Team",
        subject_type: "Repository",
        subject_id: repo_id,
      })
    }

    scope :user_indirect_read_via_children_on_repository, -> (actor_id:, subject_id:) {
      indirect_via_children.where({
        actor_id: actor_id,
        actor_type: "User",
        children: {
          subject_id: subject_id,
          subject_type: "Repository",
        },
      })
    }

    scope :user_indirect_write_via_children_on_repository, -> (actor_id:, subject_id:) {
      indirect_write_via_children.where({
        actor_id: actor_id,
        actor_type: "User",
        children: {
          subject_id: subject_id,
          subject_type: "Repository",
        },
      })
    }
  end
end
