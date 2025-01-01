# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class RepositoriesBallast < ApplicationRecord::Ballast
      self.abstract_class = true
    end
  end
end
