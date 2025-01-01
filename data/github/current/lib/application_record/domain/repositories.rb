# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Repositories < ApplicationRecord::Repositories
      self.abstract_class = true
    end
  end
end
