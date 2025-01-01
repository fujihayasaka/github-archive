# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class PublishToRepositoryTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      make_trusted_oauth_apps_owner
      create(:codespaces_integration)
    end

    test "fails if codespace isn't from a template" do
      user = create(:user)
      codespace = create(:codespace, owner: user, repository: create(:repository))

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)
      refute_predicate result, :success?
      assert result.reason.match?(/must be created from a template repository/)
    end

    test "fails if repository creation fails" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)

      erroring_repo = Repository.new
      erroring_repo.errors.add(:name, "is invalid")
      Repository.stubs(:handle_creation).returns(Repository::Creatable::Result.new(false, true, erroring_repo, "some-error"))

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)
      refute_predicate result, :success?
      assert result.reason.match?(/Name is invalid/)
    end

    test "respects the name and privacy setting" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)
      assert_equal "test-repo", result.repository.name
      assert result.repository.private?
    end

    test "updates the codespace's repository" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)
      assert_predicate result, :success?
      assert_equal codespace.reload.repository, result.repository
    end

    test "updates the permission grants for each installation for the codespace" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)
      _, installation1 = Codespaces::Tokens.grant_repository_access(user, codespace)
      _, installation2 = Codespaces::Tokens.grant_repository_access(user, codespace)

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)
      assert_predicate result, :success?
      assert_equal codespace.reload.repository, result.repository
      assert_includes installation1.reload.repository_ids, result.repository.id
      assert_includes installation2.reload.repository_ids, result.repository.id
    end

    test "creates a RepositoryClone record" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)

      assert RepositoryClone.find_by(template_repository: codespace.template_repository, clone_repository: result.repository, cloning_user: user)
    end

    test "sends the published event" do
      user = create(:user)
      codespace = create(:unpublished_codespace, owner: user)

      result = Codespaces::PublishToRepository.call(name: "test-repo", is_private: true, codespace: codespace)

      expected_message = {
        codespace: Hydro::EntitySerializer.codespace(codespace)
      }
      assert_hydro_published(expected_message, schema: "github.codespaces.v0.CodespacePublished")
    end
  end
end
