# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Vulnerabilities < ApplicationRecord::Notify
      self.abstract_class = true
    end
  end
end
