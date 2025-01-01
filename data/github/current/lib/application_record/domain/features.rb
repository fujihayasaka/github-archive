# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Features < ApplicationRecord::Mysql1
      self.abstract_class = true
    end
  end
end
