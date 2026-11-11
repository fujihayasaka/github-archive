# frozen_string_literal: true

module SinceYesterday
  extend ActiveSupport::Concern

  included do
    scope :since_yesterday, lambda {
      where(review_requested_at: 1.day.ago..).order(review_requested_at: :desc)
    }
  end
end
