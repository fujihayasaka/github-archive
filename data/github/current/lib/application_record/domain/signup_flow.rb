# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class SignupFlow < ApplicationRecord::SignupFlow
      self.abstract_class = true
    end
  end
end
