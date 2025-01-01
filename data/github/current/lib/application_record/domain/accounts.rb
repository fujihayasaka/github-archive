# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Accounts < ApplicationRecord::Accounts
      self.abstract_class = true
    end
  end
end
