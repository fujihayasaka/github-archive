# typed: true
# frozen_string_literal: true

class RepositoryAdvisoryAffectedProduct < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests

  belongs_to :repository_advisory

  validates :repository_advisory, presence: true

  # All user editable text fields must support UTF-8 and need encoding forced
  attribute :affected_versions, StringFromBinary.new
  attribute :ecosystem, StringFromBinary.new
  attribute :package, StringFromBinary.new
  attribute :patches, StringFromBinary.new

  validates :affected_versions, presence: true, if: :repository_advisory_published?
  validates :affected_versions, length: { maximum: 1024 }
  validates :ecosystem, length: { maximum: 50 }
  validates :package, length: { maximum: 100 }
  validates :patches, length: { maximum: 1024 }
  validates :affected_functions, length: { maximum: 1024 }

  def repository_advisory_published?
    repository_advisory&.published?
  end
end
