# typed: true
# frozen_string_literal: true

class MigrationRepository < ApplicationRecord::Domain::Migrations
  belongs_to :migration
  belongs_to :repository
end
