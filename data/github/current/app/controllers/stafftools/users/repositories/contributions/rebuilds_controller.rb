# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::Contributions::RebuildsController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.rebuild_contributions
    GitHub.dogstats.increment(
      "repository",
      tags: ["action:rebuild_commit_contributions", "type:user"],
    )

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Rebuild commit contributions jobs enqueued...",
    )
  end
end
