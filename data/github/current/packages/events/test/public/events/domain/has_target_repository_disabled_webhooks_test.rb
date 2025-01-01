# typed: true
# frozen_string_literal: true

require "test_helper"

class HasTargetRepositoryDisabledWebhooksTest < GitHub::TestCase
  fixtures do
    @mojombo = create(:user, login: "mojombo", plan: "medium")
    @restricted_user = create(:user)
    @repo = create(:repository, name: "grit", owner: @mojombo)
  end

  setup do
    @domain = Events::Domain.new
  end

  context "when repository is disabled" do
    test "it returns true" do
      disabled_repo = create(:private_repository, name: "disabled_repo", owner: @restricted_user)

      @restricted_user.trade_controls_restriction.full!
      result = @domain.has_target_repository_disabled_webhooks(disabled_repo)
      assert_equal true, result
    end
  end

  context "when  maintainer_love_advisory_workspaces_can_use_actions is disabled" do
    test "it returns true" do
      disable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions)

      @org = create(:organization, admin:  @mojombo, plan: "free")
      @repo1 = create(:repository, owner: @org, from_example: :simple)

      @advisory = create(:repository_advisory, repository: @repo1, author:  @mojombo)
      GitHub.context.push(actor_id:  @mojombo.id)
      @workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory,  @mojombo).tap(&:save!)
      result = @domain.has_target_repository_disabled_webhooks(@workspace_repo)
      assert_equal true, result
    end
  end
end
