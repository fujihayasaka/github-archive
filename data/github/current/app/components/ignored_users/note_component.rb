# typed: true
# frozen_string_literal: true

module IgnoredUsers
  class NoteComponent < ApplicationComponent
    def initialize(
      note:,
      target_user_login:,
      current_organization: nil,
      dialog_id:,
      return_to: nil
    )
      @note = note
      @target_user_login = target_user_login
      @current_organization = current_organization
      @return_to = return_to
      @dialog_id = dialog_id
    end

    private

    attr_reader :note, :target_user_login, :current_organization, :return_to, :dialog_id

    def unique_dialog_id
      @dialog_id
    end

    def action_text
      if note.present?
        "Edit note"
      else
        "Add note"
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
  end
end
