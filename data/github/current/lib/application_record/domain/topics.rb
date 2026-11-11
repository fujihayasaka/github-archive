# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Topics < ApplicationRecord::Mysql1
      self.abstract_class = true
    end
  end
end
