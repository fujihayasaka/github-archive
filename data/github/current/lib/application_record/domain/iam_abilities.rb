# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class IamAbilities < ApplicationRecord::IamAbilities
      self.abstract_class = true
    end
  end
end
