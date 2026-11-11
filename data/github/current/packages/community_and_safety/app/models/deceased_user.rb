# typed: true
# frozen_string_literal: true

class DeceasedUser < ApplicationRecord::Collab
  include Instrumentation::Model
  include ActionView::Helpers::DateHelper

  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  validates :user_id, presence: true, on: :create
  validates :user_id, uniqueness: { allow_nil: true }

  after_create_commit :instrument_creation, if: :user_id?

  def instrument_creation
    instrument :create,
      user: user
  end
end
