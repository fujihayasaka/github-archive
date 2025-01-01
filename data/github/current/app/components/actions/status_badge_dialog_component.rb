# typed: true
# frozen_string_literal: true

class Actions::StatusBadgeDialogComponent < ApplicationComponent
  def initialize(dialog_id:, filename:, current_repository:, lab:)
    @dialog_id = dialog_id
    @filename = filename
    @current_repository = current_repository
    @lab = lab
  end

  private

  def src_path
    workflow_badge_by_file_configure_path(workflow_filename: filename, repository: current_repository, user_id: current_repository.owner.display_login, lab: lab.presence)
  end

  attr_reader :dialog_id, :filename, :current_repository, :lab
end
