# typed: strict
# frozen_string_literal: true

class Actions::Invocation

  sig { params(actor: T.any(User, Business), staff_actor: User).void }
  def self.block(actor:, staff_actor:)

    # When the call to this method is by the `GitHub.launch_github_app.bot` we want
    # to mark the configurable entry accordingly so we know if the block was due to
    # automation or a manual action in stafftools.
    blocked_by_actions = if GitHub.launch_github_app && staff_actor.global_relay_id == GitHub.launch_github_app.bot.global_relay_id
      actor.block_action_invocation_for_reputation(staff_actor)
      true
    else
      actor.block_action_invocation(staff_actor)
      false
    end

    parent_business = nil
    if actor.is_a?(Business)
      parent_business = actor.global_relay_id
      actors_with_repos = actor.organizations
    else
      actors_with_repos = [actor]
    end

    actors_with_repos.each do |actor_with_repo|
      GlobalInstrumenter.instrument(
        "actions.invocation_blocked",
        { account: actor_with_repo }
      )

      fields = {
        "code.namespace" => self.class.name,
        "code.function" => "block",
        "gh.actions.blocked_by_actions" => blocked_by_actions,
        "gh.actions.actor.global_id" => actor.global_relay_id,
        "gh.actions.staff_actor.global_id" => staff_actor.global_relay_id,
      }
      fields["gh.business.global_id"] = parent_business if parent_business

      GitHub.logger.info("github.actions.v0.InvocationBlocked emitted", fields)
    end
  end

  sig { params(actor: T.any(User, Business), staff_actor: User).void }
  def self.unblock(actor:, staff_actor:)
    actor.unblock_action_invocation(staff_actor)
    parent_business = nil
    if actor.is_a?(Business)
      parent_business = actor.global_relay_id
      actors_with_repos = actor.organizations
    else
      actors_with_repos = [actor]
    end

    actors_with_repos.each do |actor_with_repo|
      GlobalInstrumenter.instrument(
        "actions.invocation_unblocked",
        { account: actor_with_repo }
      )

      fields = {
        "code.namespace" => self.class.name,
        "code.function" => "unblock",
        "gh.actions.actor.global_id" => actor.global_relay_id,
        "gh.actions.staff_actor.global_id" => staff_actor.global_relay_id,
      }
      fields["gh.business.global_id"] = parent_business if parent_business

      GitHub.logger.info("github.actions.v0.InvocationUnblocked emitted", fields)
    end
  end
end
