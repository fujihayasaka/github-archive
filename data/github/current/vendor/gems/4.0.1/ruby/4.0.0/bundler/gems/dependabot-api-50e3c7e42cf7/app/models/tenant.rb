# frozen_string_literal: true

class Tenant < ApplicationRecord
  has_many :accounts, inverse_of: :tenant

  validates :slug, presence: true
  validates :github_id, presence: true
end
