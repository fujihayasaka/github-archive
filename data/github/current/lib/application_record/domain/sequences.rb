# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Sequences < ApplicationRecord::Mysql1
      self.abstract_class = true
    end
  end
end
