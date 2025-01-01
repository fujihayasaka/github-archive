# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class LicensingCollab < ApplicationRecord::Collab
      self.abstract_class = true
    end
  end
end
