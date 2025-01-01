# typed: true
# frozen_string_literal: true

# A controller that reports copilot job status to `fetchPoll` pollers.
#
# Example
#
# Poll the job url returned by the controller.
#   fetchPoll('/_jobs/copilot-completion:1234...')
class CopilotJobsController < ApplicationController
  extend T::Sig

  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    return head :not_found unless current_job
    return head :not_found unless current_job.actor.id == current_user.id
    return head :not_found unless current_job.repository
    if !current_job.repository.public? && !current_job.repository.readable_by?(current_user)
      return head :not_found
    end

    status =
      if !current_job.finished?
        :accepted
      elsif current_job.success?
        :ok
      else
        :internal_server_error
      end

    render status: status, json: { job: current_job.as_json }
  end

  private

  memoize def current_job
    Copilot::CompletionJobStatus.find(params[:id])
  end

  sig { returns(T.any(Copilot::CompletionJobStatus, Symbol)) }
  def resource_for_conditional_access
    current_job || :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    current_job&.target_for_conditional_access || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
