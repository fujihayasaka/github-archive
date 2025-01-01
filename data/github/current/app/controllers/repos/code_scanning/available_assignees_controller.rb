# typed: strict
# frozen_string_literal: true

class Repos::CodeScanning::AvailableAssigneesController < AbstractRepositoryController
  include ScanningControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer

  before_action :check_code_scanning_write

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    only: [:index]

  sig { void }
  def index
    return render_404 unless current_repository.code_scanning_alert_assignment_enabled?

    # First retrieve all users that can be assigned to alerts. We will later filter this down to users that also have
    # code scanning write access.
    ids = current_repository.available_assignee_ids(limit: 10_000)

    scope = User.where(id: ids).includes(:profile)
    scope = scope.order("login").filter_spam_for(current_user)

    query = ActiveRecord::Base.sanitize_sql_like(
      params[:query].to_s.strip.downcase,
    )

    if query.present?
      scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                  .where(["users.login LIKE ? OR profiles.name LIKE ?", "%#{query}%", "%#{query}%"])
    end

    # Now that we have the users, we need to filter them down to only those that have code scanning write access.
    users = Promise.all(scope.map do |user|
      current_repository.async_code_scanning_allowed?(:write_code_scanning, user).then do |allowed|
        if allowed
          user
        else
          nil
        end
      end
    end).sync.filter(&:present?)

    # If the Copilot SWE agent is enabled, we need to add it to the list of
    # available assignees. This could include all globally assignable apps, or
    # all apps that are installed and assignable in the repository - but as we're
    # specifically checking for copilot_swe_agent_enabled?, we should only include that one.
    # This is based on https://github.com/github/github/blob/d25913df950c9a647307878a807dfd5200596fce/app/platform/helpers/assignees_helper.rb#L33
    # and https://github.com/github/github/blob/10b261136f672374f7c9097d4476e149ec26d9a5/app/platform/loaders/integration_installation/repository_for_viewer.rb#L17
    if current_repository.copilot_swe_agent_enabled?(current_user)
      integration = ::Apps::Privileged.integration(:copilot_swe_agent)

      if query.blank? || integration.name.downcase.include?(query.downcase) || integration.slug.downcase.include?(query.downcase)
        users << integration.bot
      end

      users.uniq
    end

    render json: {
      users: users.map do |user|
        serialized_assignee(user)
      end
    }
  end
end
