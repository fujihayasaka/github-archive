# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class PreGhasSKUTrialEnabledRepository < ApplicationRecord::Domain::SecurityProductsEnablement
    validates :repository_id, presence: true
    validates :target_id, presence: true
    validates :target_type, presence: true
    validates :sku_name, presence: true
  end
end
