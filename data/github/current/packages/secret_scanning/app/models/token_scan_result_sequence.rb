# typed: true
# frozen_string_literal: true

class TokenScanResultSequence < ApplicationRecord::TokenScanningService
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
end
