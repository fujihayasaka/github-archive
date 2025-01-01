# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Iam < ApplicationRecord::Iam
      self.abstract_class = true
    end
  end
end
