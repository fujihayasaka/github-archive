# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class AssetKeyValues < ApplicationRecord::Assets
      self.abstract_class = true
    end
  end
end
