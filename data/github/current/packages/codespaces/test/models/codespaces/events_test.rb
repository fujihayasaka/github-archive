# typed: true
# frozen_string_literal: true

require "test_helper"

class EventsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @monalisa = create(:paid_user, name: "monalisa")
    @repo = create(:repository, name: "test-repo", owner: @monalisa, from_example: :pull_request_source)
    @codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch)
  end

  test "#start publishes message with codespace and actor" do
    Codespaces::Events.start(@codespace)

    message = {
      codespace: Hydro::EntitySerializer.codespace(@codespace),
      actor: Hydro::EntitySerializer.user(@codespace.owner)
    }

    assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceStart")
  end

  test "#suspend publishes message with codespace and actor" do
    Codespaces::Events.suspend(@codespace)

    message = {
      codespace: Hydro::EntitySerializer.codespace(@codespace),
      actor: Hydro::EntitySerializer.user(@codespace.owner)
    }

    assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSuspend")
  end

  context "#interaction" do
    test "publishes message with codespace and actor" do
      Codespaces::Events.interaction(codespace: @codespace, type: :FILE_CHANGED)

      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        actor: Hydro::EntitySerializer.user(@codespace.owner),
        type: :FILE_CHANGED,
        source: nil,
        client: nil,
        forked_from_onboarding_repo: false,
        attempted_from_prebuild: false
      }

      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceInteraction")
    end

    test "source is set in the hydro payload when provided" do
      Codespaces::Events.interaction(codespace: @codespace, type: :FILE_CHANGED, source: "cli")

      hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
      assert_equal("cli", hydro_payload[:source])
    end

    test "client is set in the hydro payload when provided" do
      Codespaces::Events.interaction(codespace: @codespace, type: :FILE_CHANGED, client: "web")

      hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
      assert_equal("web", hydro_payload[:client])
    end

    test "attempted_from_prebuild is set in the hydro payload to true when codespace is from a prebuild" do
      @codespace.update(environment_data: { "createFromPrebuild": true })
      Codespaces::Events.interaction(codespace: @codespace, type: :FILE_CHANGED)

      hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
      assert hydro_payload[:attempted_from_prebuild]
    end

    context "forked_from_onboarding_repo" do
      test "sets to true when the codespaces repo is forked from onboarding repo" do
        owner = create(:user, name: "github")
        onboarding_repo = create(:repository, name: Codespaces::Events::ONBOARDING_REPO_NAME, owner: owner)
        forked_repo = create(:fork_repository, forker: @monalisa, fork_repo: onboarding_repo)

        codespace = create(:codespace, repository: forked_repo)
        Codespaces::Events.interaction(codespace: codespace, type: :FILE_CHANGED)

        hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
        assert_equal(true, hydro_payload[:forked_from_onboarding_repo])
      end

      test "sets to false when the codespaces repo is not forked from onboarding repo" do
        random_repo = create(:repository, name: "not-onboarding", owner: @monalisa)
        forked_repo = create(:fork_repository, forker: @monalisa, fork_repo: random_repo)
        codespace = create(:codespace, repository: forked_repo)
        Codespaces::Events.interaction(codespace: codespace, type: :FILE_CHANGED)

        hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
        assert_equal(false, hydro_payload[:forked_from_onboarding_repo])
      end
    end
  end
end
