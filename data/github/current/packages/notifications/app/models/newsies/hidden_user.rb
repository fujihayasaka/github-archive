# encoding: utf-8
# typed: true
# frozen_string_literal: true

module Newsies
  class HiddenUser < ApplicationRecord::Domain::Notifications
    self.utc_datetime_columns = [:created_at]

    def self.hide_user(user_id)
      begin
        create!(user_id: user_id)
      rescue ActiveRecord::RecordNotUnique
        # The hidden user already exists.
      end
    end

    def self.unhide_user(user_id)
      raise ArgumentError, "user_id must be numeric" unless user_id.is_a? Numeric

      where(user_id: user_id).delete_all
    end
  end
end
