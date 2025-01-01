# typed: true
# frozen_string_literal: true

require "test_helper"

module ActionsPrompt
  class FlamingoActionsTest < GitHub::TestCase
    fixtures do
      @monalisa = create(:paid_user, name: "monalisa")
      @free_org = create(:organization, admin: @monalisa, plan: "business_plus")
      @team_org = create(:organization, admin: @monalisa, plan: "business")
      @ghec_org = create(:organization, admin: @monalisa, plan: "business_plus")
      @team_org_repo = create(:repository, name: "test-repo", owner: @team_org)
      @non_org_repo = create(:repository, name: "test-repo-mona", owner: @monalisa)
      @ghec_org_repo = create(:repository, name: "test-repo-ghec", owner: @ghec_org)
      @free_org_repo = create(:repository, name: "test-repo-free", owner: @free_org)
    end

    context "#allowed_experience?" do
      test "returns true if repository is in munger and team org repo" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns({ "entity_id" => @team_org_repo.id, "propensity_score" => 2 })

        assert FlamingoActions
          .new(@team_org_repo)
          .allowed_experience?
      end

      test "returns false if there is no flamingo info" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns(nil)

        refute FlamingoActions
          .new(@repo)
          .allowed_experience?
      end

      test "returns false if the repository has CI" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns({ "entity_id" => @team_org_repo.id, "propensity_score" => 2 })

        Marketplace::Domain::RepositorySettings.any_instance.stubs(:has_ci?).returns(true)

        refute FlamingoActions
          .new(@repo)
          .allowed_experience?
      end

      test "returns false if repo is not org owned" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns({ "entity_id" => @non_org_repo.id, "propensity_score" => 2 })

        refute FlamingoActions
          .new(@non_org_repo)
          .allowed_experience?
      end

      test "returns false if repo is GHEC org owned" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns({ "entity_id" => @ghec_org_repo.id, "propensity_score" => 2 })

        refute FlamingoActions
          .new(@ghec_org_repo)
          .allowed_experience?
      end

      test "returns false if repo is free org owned" do
        Munger::Client
          .any_instance
          .stubs(:flamingo_adoption_for_repository)
          .returns({ "entity_id" => @free_org_repo.id, "propensity_score" => 2 })

        refute FlamingoActions
          .new(@free_org_repo)
          .allowed_experience?
      end
    end
  end unless GitHub.enterprise?
end
