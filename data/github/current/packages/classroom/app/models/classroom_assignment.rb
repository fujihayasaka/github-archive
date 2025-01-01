# typed: true
# frozen_string_literal: true

class ClassroomAssignment < ApplicationRecord::Domain::Classroom
  include Repositories::BelongsToRepository

  # rubocop:todo Rails/InverseOf
  belongs_to :classroom, class_name: "ClassroomClassroom", foreign_key: :classroom_classroom_id
  # rubocop:enable Rails/InverseOf
  belongs_to_repository_via_domain relation_name: :starter_code_repository, foreign_key: :starter_code_repository_id, class_name: "Repository", optional: true, feature_flag: "repos_domain_associations"

  has_many :classroom_repositories, dependent: :destroy

  validates :name, presence: true
  validates :name, length: { maximum: 60 }
  validates :assignment_type, presence: true
  validates :classroom_classroom_id, presence: true
end
