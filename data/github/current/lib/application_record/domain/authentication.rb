# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Authentication < ApplicationRecord::Authnd
      self.abstract_class = true
    end
  end
end
