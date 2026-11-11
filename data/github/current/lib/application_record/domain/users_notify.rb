# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class UsersNotify < ApplicationRecord::Notify
      self.abstract_class = true
    end
  end
end
