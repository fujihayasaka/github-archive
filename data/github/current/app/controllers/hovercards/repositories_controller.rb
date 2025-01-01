# typed: true
# frozen_string_literal: true

class Hovercards::RepositoriesController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %(show).freeze

  before_action :require_xhr, only: :show

  def show

    hydro_data = params.slice(:event_type, :hover_target, :user_id, :subject, :payload).to_unsafe_h

    render "hovercards/repositories/show", locals: { repository: current_repository, hydro_data: hydro_data }, layout: false
  end
end
