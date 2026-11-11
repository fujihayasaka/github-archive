# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class AssetObjects < ApplicationRecord::Mysql1
      self.abstract_class = true
    end
  end
end
