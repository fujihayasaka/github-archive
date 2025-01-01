# typed: true
# frozen_string_literal: true

class Discussions::LeaderboardsController < Discussions::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    leaderboard = DiscussionLeaderboard.new(repository: current_repository, viewer: current_user)

    if params[:show_v2]
      render "discussions/leaderboards/show_v2", layout: false, locals: { leaderboard: leaderboard }
    else
      render "discussions/leaderboards/show", layout: false, locals: { leaderboard: leaderboard }
    end
  end
end
