# typed: true
# frozen_string_literal: true

class MannequinClaim < ApplicationRecord::Domain::Users
  belongs_to :mannequin, class_name: "Mannequin"
  belongs_to :claimant, class_name: "User"
end
