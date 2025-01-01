# typed: true
# frozen_string_literal: true

class Orgs::TeamDiscussions::TransferButtonsController < Orgs::Controller
  include Orgs::TeamDiscussions::TransferControllerMethods

  before_action :login_required
  before_action :this_team_required
  before_action :ensure_discussions_available

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Repositories,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::Spokes

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    return head :ok if candidate_repositories.empty?

    render partial: "orgs/team_discussions/transfer_button", locals: {
      organization: this_organization,
      team_slug: this_team.slug
    }, formats: :html
  end
end
