# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class SearchMysql5 < ApplicationRecord::Mysql5
      self.abstract_class = true
    end
  end
end
