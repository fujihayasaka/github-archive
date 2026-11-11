# typed: true
# frozen_string_literal: true

module SecretScanning
  class OwnerScope < ApplicationRecord::TokenScanningService
    enum :owner_scope, {
      repo: "REPO",
      org: "ORG",
      business: "BIZ",
      user: "USER",
    }
    scope :not_user, -> { where.not(owner_scope: :user) }

    validates_presence_of :owner_id, :owner_scope
  end
end
