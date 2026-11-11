# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::InvocationController < StafftoolsController
  before_action :ensure_repo_exists

  def create
    current_repository.unblock_action_invocation(current_user)

    if FeatureFlag.vexi.enabled?(:actions_send_repo_in_invocation_event, default: false)
      GlobalInstrumenter.instrument(
        "actions.invocation_unblocked",
        {
          account: current_repository.owner,
          repository: current_repository
        }
      )
      fields = {
        "code.namespace" => self.class.name,
        "code.function" => "unblock",
        "gh.actions.actor.global_id" => current_repository.owner.global_relay_id,
        "gh.actions.staff_actor.global_id" => current_user.global_relay_id,
      }

      GitHub.logger.info("github.actions.v0.InvocationUnblocked emitted", fields)
    end

    flash[:notice] = "Action invocation unblocked."
    redirect_to :back
  end

  def destroy
    current_repository.block_action_invocation(current_user)
    if FeatureFlag.vexi.enabled?(:actions_send_repo_in_invocation_event, default: false)
      GlobalInstrumenter.instrument(
        "actions.invocation_blocked",
        {
          account: current_repository.owner,
          repository: current_repository
        }
      )
      fields = {
        "code.namespace" => self.class.name,
        "code.function" => "block",
        "gh.actions.actor.global_id" => current_repository.owner.global_relay_id,
        "gh.actions.staff_actor.global_id" => current_user.global_relay_id,
      }

      GitHub.logger.info("github.actions.v0.InvocationBlocked emitted", fields)
    end

    flash[:notice] = "Action invocation blocked."
    redirect_to :back
  end
end
