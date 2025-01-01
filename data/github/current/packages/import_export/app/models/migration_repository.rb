# typed: true
# frozen_string_literal: true

class MigrationRepository < ApplicationRecord::Domain::Migrations
  belongs_to :migration
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
end
