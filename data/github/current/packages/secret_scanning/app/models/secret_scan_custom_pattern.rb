# typed: true
# frozen_string_literal: true

class SecretScanCustomPattern < ApplicationRecord::TokenScanningService

  belongs_to :owner, class_name: "Organization"
  belongs_to :repository

  enum :scope, {
    unknown: 0,
    repo: 1,
    org: 2,
    business: 3,
  }

  validates_presence_of :owner_id, :scope, :secret_type, :slug, :display_name, :expression

  def self.create_repo_pattern!(repo, attributes)
    repo.secret_scan_custom_patterns.create!(attributes.merge({ scope: :repo, owner_id: repo.owner.id }))
  end
end
