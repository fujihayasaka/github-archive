# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Migrations < ApplicationRecord::Migrations
      self.abstract_class = true
    end
  end
end
