# typed: true
# frozen_string_literal: true
class ReminderTeamMembership < ApplicationRecord::Collab
  belongs_to :reminder
  belongs_to :team
end
