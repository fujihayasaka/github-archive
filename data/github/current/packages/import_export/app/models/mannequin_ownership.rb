# typed: true
# frozen_string_literal: true

class MannequinOwnership < ApplicationRecord::Domain::Users
  belongs_to :mannequin, class_name: "Mannequin"
  belongs_to :owner, class_name: "Organization"
end
