# typed: true
# frozen_string_literal: true

class KeyboardShortcutsController < ApplicationController
  include KeyboardShortcutsHelper

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # CAP is not required - this controller returns public information that is not owned by any org or business
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    respond_to do |format|
      format.html do
        if serving_gist_standalone?
          render "site/gist_keyboard_shortcuts", layout: false
        else
          render Site::KeyboardShortcutsComponent.new(user: current_user, contexts: params[:contexts]), layout: false
        end
      end
      format.json do
        shortcuts = ui_commands_for_contexts(current_user, params[:contexts])
        shortcuts.compact!
        render json: { commands: shortcuts.reduce({}, :merge) }
      end
    end
  end
end
