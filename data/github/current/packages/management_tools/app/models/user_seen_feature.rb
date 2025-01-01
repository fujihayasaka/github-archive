# typed: true
# frozen_string_literal: true

class UserSeenFeature < ApplicationRecord::Collab
  belongs_to :user
  belongs_to :feature
end
