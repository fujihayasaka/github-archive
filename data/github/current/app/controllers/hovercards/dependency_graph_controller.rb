# typed: true
# frozen_string_literal: true
class Hovercards::DependencyGraphController < AbstractRepositoryController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    return render_404 if !check_access_permissions

    repository = Repositories::Public.find_active!(params[:package_repository_id])
    return render_404 unless repository.public?

    render "hovercards/dependency_graph/show",
      locals: {
        package_name: params[:package_name],
        repository: repository,
      },
      layout: false
  end

  private

  def target_type # rubocop:todo GitHub/UseRestfulActions
    # Needed by Hovercards::ConditionalAccessMethods to display in the error message when hovercard is being viewed from a non-allowed IP address.
    "dependency graph package"
  end

  def check_access_permissions
    current_repository.public? || current_user_can_read_repo?
  end
end
