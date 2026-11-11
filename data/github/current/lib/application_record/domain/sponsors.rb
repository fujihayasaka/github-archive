# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Sponsors < ApplicationRecord::Collab
      self.abstract_class = true
    end
  end
end
