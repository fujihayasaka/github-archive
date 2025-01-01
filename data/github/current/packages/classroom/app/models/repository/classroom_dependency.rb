# typed: true
# frozen_string_literal: true

# This mixin includes repo-adjacent functionality that is for repositories related to Classroom.
module Repository::ClassroomDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    has_one :classroom_repository
    has_one :classroom_assignment, foreign_key: :starter_code_repository_id, inverse_of: :starter_code_repository
  end

  def starter_code_repository
    classroom_repository&.starter_code_repository
  end

  def creation_handled_by_classroom?
    # You can end up here if you're a student accepting an assignment through Classroom
    # You can also end up here if you're a teacher duplicating a Classroom assignment that has starter code which
    # points to a repo that is not available in the target organization.
    starter_code_repository || classroom_assignment
  end
end
