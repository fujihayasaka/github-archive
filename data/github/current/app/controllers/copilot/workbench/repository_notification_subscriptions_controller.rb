# typed: strict
# frozen_string_literal: true

class Copilot::Workbench::RepositoryNotificationSubscriptionsController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  allow_verified_fetch

  before_action :try_parse_json_params
  before_action :require_workbench

  sig { void }
  def create
    workbench = T.must(self.workbench)
    repository_id = workbench.repository_id
    if !repository_id
      return render json: { subscribed: false, message: "No repository found for Workbench" }, status: :ok
    end
    repository = T.cast(Repositories.domain.by_id(workbench.repository_id), Repository) # rubocop:disable GitHub/AvoidCast
    channel = GitHub::WebSocket::Channels.signed_branch(repository, repository.default_branch)

    render json: { subscribed: true, channel: channel, message: "Success" }, status: :ok
  end

  private

  sig { returns T.nilable(Spark::Workbench) }
  memoize def workbench
    Spark::Workbench.for_uuid_string(current_user.id, params[:id])
  end

  sig { void }
  def require_workbench
    render_404 unless workbench
  end
end
