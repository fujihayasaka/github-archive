# typed: true
# frozen_string_literal: true

class EditRepositories::DiscussionActivationController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :add_spamurai_form_signals, only: [:update]
  before_action :ensure_user_can_toggle, only: [:update]

  def update
    if current_repository.org_discussion_source?
      not_allowed
    else
      toggle_discussions_for_repository
    end
  end

  private

  def ensure_user_can_toggle
    unless current_repository.can_toggle_discussions_setting?(current_user)
      render_404
    end
  end

  def not_allowed
    head :bad_request
  end

  def toggle_discussions_for_repository
    if params[:has_discussions] == "1"
      current_repository.turn_on_discussions(actor: current_user)
    else
      current_repository.turn_off_discussions(actor: current_user)
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :repo_settings,
            display_variant: :padded,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        else
          head :ok
        end
      end

      format.all do
        head :ok
      end
    end
  end
end
