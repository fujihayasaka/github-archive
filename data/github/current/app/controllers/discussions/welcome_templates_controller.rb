# typed: true
# frozen_string_literal: true

class Discussions::WelcomeTemplatesController < Discussions::BaseController
  before_action :login_required
  before_action :require_permission_to_toggle_discussions_setting
  before_action :require_verified_email
  skip_before_action :require_feature

  def create
    current_repository = T.must_because(self.current_repository) do
      "#require_permission_to_toggle_discussions_setting ensures non-nil"
    end
    current_repository.turn_on_discussions(actor: current_user)

    redirect_to new_discussion_path(
      current_repository.owner,
      current_repository,
      welcome_text: true,
      category: default_category&.slug,
    )
  end

  def landing # rubocop:todo GitHub/UseRestfulActions
    current_repository = T.must_because(self.current_repository) do
      "#require_permission_to_toggle_discussions_setting ensures non-nil"
    end
    if current_repository.show_landing_page?(current_user)
      render "discussions/landing"
    else
      redirect_to(repository_path(current_repository))
    end
  end

  private

  def require_permission_to_toggle_discussions_setting
    render_404 unless current_repository&.can_toggle_discussions_setting?(current_user)
  end

  def require_verified_email
    if current_user.should_verify_email?
      flash[:error] = "You can't perform that action at this time."
      current_repository = T.must_because(self.current_repository) do
        "#require_permission_to_toggle_discussions_setting ensures non-nil"
      end
      redirect_to discussions_path(current_repository.owner, current_repository)
    end
  end

  def default_category
    current_repository = T.must_because(self.current_repository) do
      "#require_permission_to_toggle_discussions_setting ensures non-nil"
    end
    category = current_repository.available_discussion_categories.find_by(name: DiscussionCategory::ANNOUNCEMENTS_NAME)
    category ||= current_repository.fallback_discussion_category!
  end
end
