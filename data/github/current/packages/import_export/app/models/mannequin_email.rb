# typed: true
# frozen_string_literal: true

class MannequinEmail < ApplicationRecord::Domain::Users
  include GitHub::Validations
  belongs_to :mannequin
  validates :email, unicode3: true

  scope :verified, -> { none }
  scope :visible, -> { none }

  def public?
    false
  end
end
