# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class InProductTargeting < ApplicationRecord::InProductTargeting
      self.abstract_class = true
    end
  end
end
