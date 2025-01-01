# typed: true
# frozen_string_literal: true

class MemexProjectVisit < ApplicationRecord::Domain::Memexes
  belongs_to :memex_project, required: true
  belongs_to :viewer, required: true, class_name: "User"
  belongs_to :owner, polymorphic: true, required: true

  validates :viewer, presence: true
  validates :memex_project, presence: true, uniqueness: { scope: :viewer, message: "visit already exists for viewer and project" }
  validates :owner, presence: true
  validates :last_visited_at, presence: true
end
