# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class RepositoriesPushes < ApplicationRecord::RepositoriesPushes
      self.abstract_class = true
    end
  end
end
