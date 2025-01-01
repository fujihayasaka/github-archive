# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Copilot < ApplicationRecord::Copilot
      self.abstract_class = true
    end
  end
end
