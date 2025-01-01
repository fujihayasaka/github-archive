# typed: true
# frozen_string_literal: true

class InProductMessagingSubscription < ApplicationRecord::Domain::Users
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true
  validates :subscribed, inclusion: { in: [true, false] }
end
