# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Packages < ApplicationRecord::Repositories
      self.abstract_class = true
    end
  end
end
