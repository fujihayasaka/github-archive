# typed: true
# frozen_string_literal: true

class MigratableResourceReport < ApplicationRecord::Domain::Migrations
  belongs_to :migration

  validates :migration, presence: true
  validates :model_type, presence: true
  validates :total_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :success_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :failure_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

end
