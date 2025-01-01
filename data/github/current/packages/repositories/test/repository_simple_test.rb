# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositorySimpleTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @repo = create(:repository, name: "test")
    @user = create(:user)
  end

  if GitHub.interaction_limits_enabled?
    test "making the repository private disables its interaction limits" do
      repo = create(:repository)
      ability = RepositoryInteractionAbility.new(repo)
      ability.set_ability(:collaborators_only, repo.owner)
      refute ability.sockpuppet_disallowed_enabled?
      refute ability.contributors_only_enabled?
      assert ability.collaborators_only_enabled?

      perform_enqueued_hydro_jobs(only: [HydroDisableRepositoryInteractionLimitsVisibilityChangedJob]) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          repo.toggle_visibility(actor: repo.owner, visibility: "private")
        end
      end

      refute ability.sockpuppet_disallowed_enabled?
      refute ability.contributors_only_enabled?
      refute ability.collaborators_only_enabled?
    end
  end

  context "made_private?" do
    test "true when repository is privatized" do
      owner = create(:user, plan: "medium")
      repo = create(:repository, owner: owner)
      repo.private = true
      repo.save!
      assert repo.made_private?
    end

    test "false when repository is publicized" do
      owner = create(:user, plan: "medium")
      repo = create(:private_repository, owner: owner)
      repo.private = false
      repo.save!
      refute repo.made_private?
    end
  end
end
