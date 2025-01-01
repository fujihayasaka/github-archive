# typed: true
# frozen_string_literal: true
class DeceasedUser < ApplicationRecord::Collab
  include Instrumentation::Model
  include ActionView::Helpers::DateHelper

  belongs_to :user, required: true
  validates :user_id, uniqueness: true

  after_create_commit :instrument_creation

  def instrument_creation
    instrument :create,
      user: user
  end
end
