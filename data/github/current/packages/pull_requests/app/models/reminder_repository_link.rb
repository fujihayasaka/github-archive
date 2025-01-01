# typed: true
# frozen_string_literal: true
class ReminderRepositoryLink < ApplicationRecord::Collab
  belongs_to :reminder
  belongs_to :repository
end
