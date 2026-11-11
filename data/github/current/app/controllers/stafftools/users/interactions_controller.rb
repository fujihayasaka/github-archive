# typed: true
# frozen_string_literal: true

class Stafftools::Users::InteractionsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    instrument("staff.view_user_interactions", user: this_user)

    blocking_users = this_user.ignored_by
    blocked_users = this_user.ignored
    followed_users = this_user.following
    all_users = [this_user] + (blocking_users | blocked_users | followed_users)
    GitHub::PrefillAssociations.prefill_associations(all_users, :profile)

    render "stafftools/users/interactions/index", locals: {
      user: this_user,
      blocking_users: blocking_users,
      blocked_users: blocked_users,
      followed_users: followed_users,
    }
  end
end
