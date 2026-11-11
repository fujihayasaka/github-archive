# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class Gitbackups < ApplicationRecord::Gitbackups
      self.abstract_class = true
    end
  end
end
