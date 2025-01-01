# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Api < ApplicationRecord::Ballast
      self.abstract_class = true
    end
  end
end
