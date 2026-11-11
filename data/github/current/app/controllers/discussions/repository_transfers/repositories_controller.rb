# typed: true
# frozen_string_literal: true

class Discussions::RepositoryTransfers::RepositoriesController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_ability_to_transfer_discussion

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    render Discussions::Transfers::CandidateRepositoriesComponent.new(
      discussion: discussion,
      query: params[:query],
    )
  end

  private

  def require_ability_to_transfer_discussion
    render_404 unless discussion&.transferrable_by?(current_user)
  end
end
