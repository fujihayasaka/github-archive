# typed: true
# frozen_string_literal: true

require "application_record/mysql1"

module ApplicationRecord
  module Domain
    class Showcases < ApplicationRecord::Mysql1
      self.abstract_class = true
    end
  end
end
