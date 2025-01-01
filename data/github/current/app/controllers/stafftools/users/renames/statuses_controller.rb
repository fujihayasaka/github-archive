# typed: true
# frozen_string_literal: true

class Stafftools::Users::Renames::StatusesController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    user = User.find_by(id: params[:user_id])
    return render_404 unless user

    if user.renaming?
      head 202
    else
      render "stafftools/users/renames/statuses/show", locals: { user: user }, layout: false
    end
  end
end
