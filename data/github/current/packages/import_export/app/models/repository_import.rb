# typed: true
# frozen_string_literal: true

class RepositoryImport < ApplicationRecord::Domain::Imports

  belongs_to :import
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain

  validates_presence_of :import, :repository
end
