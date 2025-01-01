# typed: true
# frozen_string_literal: true

class Discussions::CategoryMenusController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    categories = current_repository.available_discussion_categories_for_actor(current_user)

    # A discussion WITH a poll can only be moved to categories that support polls
    if discussion&.poll.present?
      categories = categories.where(supports_polls: true)
    # A discussion WITHOUT a poll can only be moved to categories that DO NOT support polls
    elsif !discussion&.poll.present?
      categories = categories.where(supports_polls: false)
    end

    render "discussions/category_menus/show", layout: false, locals: {
      categories: categories,
      discussion: discussion,
    }
  end
end
