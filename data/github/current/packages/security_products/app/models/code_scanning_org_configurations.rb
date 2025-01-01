# typed: true
# frozen_string_literal: true

class CodeScanningOrgConfigurations < ApplicationRecord::Notify
  belongs_to :organization

  validates :organization, presence: true
  validates :organization, uniqueness: true

  def self.codeql_packs(repository)
    if repository.owner&.organization?
      CodeScanningOrgConfigurations.find_by(organization_id: repository.owner_id)&.codeql_packs
    end
  end
end
