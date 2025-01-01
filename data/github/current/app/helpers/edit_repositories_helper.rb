# typed: false
# frozen_string_literal: true

module EditRepositoriesHelper

  def show_archive_program_settings?
    current_repository.can_participate_in_archive_program?
  end

  def is_codespace_dotfiles_repo?(user, repo)
    user.codespace_dotfiles_enabled? && user.codespace_dotfiles_repository.present? && (repo.id == user.codespace_dotfiles_repository.id)
  end
end
