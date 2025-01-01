# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Notifications < ApplicationRecord::Mysql2
      include ApplicationRecord::UTCRecord

      self.abstract_class = true
    end
  end
end
