# typed: true
# frozen_string_literal: true

class Stafftools::StaffNoteComponent < ApplicationComponent
  include AvatarHelper

  attr_reader :note

  def initialize(note:)
    @note = note
  end

  private

  def update_path
    if note.notable.is_a?(::Business)
      stafftools_enterprise_note_path(note.notable, note)
    else
      stafftools_user_note_path(note.notable, note)
    end
  end
end
