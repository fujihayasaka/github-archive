# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Commits < ApplicationRecord::Commits
      self.abstract_class = true
    end
  end
end
