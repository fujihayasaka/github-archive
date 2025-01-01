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

    validates_presence_of :owner_id, :owner_scope
  end
end
