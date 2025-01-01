# typed: true
# frozen_string_literal: true

module IgnoredUsers
  class NoteComponent < ApplicationComponent
    DIALOG_ID = "ignored-user-note-dialog"

    def initialize(
      note:,
      target_user_login:,
      current_organization: nil,
      width_full: false,
      return_to: nil
    )
      @note = note
      @target_user_login = target_user_login
      @current_organization = current_organization
      @width_full = width_full
      @return_to = return_to
    end

    private

    attr_reader :note, :target_user_login, :current_organization, :return_to

    def unique_dialog_id
      "#{DIALOG_ID}-#{target_user_login}"
    end

    def action_text
      if note.present?
        "Edit Note"
      else
        "Add Note"
      end
    end

    def form_action_path(clear: false)
      if current_organization.present?
        organization_settings_blocked_user_path(
          current_organization,
          login: target_user_login,
          return_to: return_to,
          clear: clear,
        )
      else
        settings_blocked_user_path(target_user_login, return_to: return_to, clear: clear)
      end
    end

    def submit_button_text
      if note.present?
        "Update"
      else
        "Create"
      end
    end

    def width_full?
      @width_full
    end
  end
end
