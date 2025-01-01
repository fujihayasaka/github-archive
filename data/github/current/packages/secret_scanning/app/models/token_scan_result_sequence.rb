# typed: true
# frozen_string_literal: true

class TokenScanResultSequence < ApplicationRecord::TokenScanningService
  belongs_to :repository
end
