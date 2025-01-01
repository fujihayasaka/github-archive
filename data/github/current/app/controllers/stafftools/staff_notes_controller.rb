# typed: true
# frozen_string_literal: true

class Stafftools::StaffNotesController < StafftoolsController
  before_action :notable_required
  before_action :staff_note_required, only: %i(update destroy)

  def create
    note = StaffNote.new(note_params)

    if note.save
      redirect_to redirect_path, notice: "Note added."
    else
      flash[:error] = "Unable to create note."
      redirect_to redirect_path
    end
  end

  def update
    if T.must(note).update(update_pinned_note_params)
      redirect_to redirect_path, notice: "Note updated."
    else
      flash[:error] = "Unable to update note."
      redirect_to redirect_path
    end
  end

  def destroy
    if T.must(note).destroy
      redirect_to redirect_path, notice: "Note deleted."
    else
      flash[:error] = "Unable to delete note."
      redirect_to redirect_path
    end
  end

  private

  memoize def note
    StaffNote.find_by(id: params[:id])
  end

  def staff_note_required
    render_404 unless note.present?
  end

  memoize def this_business
    ::Business.find_by(slug: params[:slug]) if params[:slug].present?
  end

  def notable
    this_business || this_user
  end

  def notable_required
    render_404 unless notable.present?
  end

  def redirect_path
    if this_business
      stafftools_enterprise_path(this_business)
    else
      stafftools_user_overview_path(this_user)
    end
  end

  def note_params
    {
      user: current_user,
      notable: notable,
      note: params.dig(:staff_note, :note),
      is_pinned: params.key?(:is_pinned)
    }
  end

  def update_pinned_note_params
    {
      user: current_user,
      note: params.dig(:staff_note, :note),
      is_pinned: params.dig(:staff_note, :is_pinned) == "true"
    }
  end
end
