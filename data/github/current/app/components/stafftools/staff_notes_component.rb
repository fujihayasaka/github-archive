# typed: true
# frozen_string_literal: true

class Stafftools::StaffNotesComponent < ApplicationComponent
  include AvatarHelper

  attr_reader :notable

  def initialize(notable:)
    @notable = notable
  end

  private

  def notable_display_name
    if notable.is_a?(::Business)
      notable.name
    else
      notable.display_login
    end
  end

  def create_path
    if notable.is_a?(::Business)
      stafftools_enterprise_notes_path(notable)
    else
      stafftools_user_notes_path(notable)
    end
  end

  def new_note
    notable.staff_notes.new
  end

  def pinned_staff_note?
    pinned_staff_note.present?
  end

  memoize def pinned_staff_note
    scope = notable.staff_notes.pinned
    scope.where.not(user: github) if github
    scope.first
  end

  memoize def staff_notes
    scope = notable.staff_notes.unpinned
    scope.where.not(user: github) if github
    scope.order("created_at DESC").to_a
  end

  memoize def github
    ::User.find_by(login: "github")
  end
end
