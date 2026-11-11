# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Stafftools::DiscussionSubscriptionsController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests

  before_action :ensure_repo_exists
  before_action :ensure_discussion_exists

  layout "layouts/stafftools/repository/collaboration"

  def index
    watchers = Stafftools::Newsies.subscriptions_for_issue(this_discussion)
    ignorers = Stafftools::Newsies.users_ignoring_issue(this_discussion)
    repo_ignorers =
      Stafftools::Newsies.users_ignoring_repository(current_repository)

    render "stafftools/discussion_subscriptions/index", locals: {
      watchers: watchers,
      ignorers: ignorers,
      repo_ignorers: repo_ignorers,
    }
  end

end
