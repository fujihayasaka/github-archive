# typed: true
# frozen_string_literal: true

class ExternalIdentityRefreshToken < ApplicationRecord::Domain::Users
  belongs_to :external_identity

  validates :external_identity, presence: true
  validates :refresh_token, presence: true
end
