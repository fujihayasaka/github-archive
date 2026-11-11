# typed: true
# frozen_string_literal: true

class EditRepositories::CommitCommentsController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :add_spamurai_form_signals, only: [:update]

  def update
    if params[:has_commit_comments] == "1"
      current_repository.enable_commit_comments(actor: current_user)
    else
      current_repository.disable_commit_comments(actor: current_user)
    end

    head :ok
  end
end
