# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::StaffNotesController < Stafftools::SponsorsController
  def create
    staff_note = this_listing.staff_notes.new(staff_note_params.merge(user: current_user))

    if staff_note.save
      flash[:notice] = "Okay, added staff note."
    else
      errors = staff_note.errors.full_messages.join(", ")
      flash[:error] = "Could not add staff note: #{errors}"
    end

    if FeatureFlag.vexi.enabled?(:stabilize_fix_staff_notes_redirect, default: false)
      redirect_back fallback_location: stafftools_sponsors_member_path(this_listing.sponsorable)
    else
      redirect_to :back
    end
  end

  private

  def staff_note_params
    params.require(:staff_note).permit(:note)
  end
end
