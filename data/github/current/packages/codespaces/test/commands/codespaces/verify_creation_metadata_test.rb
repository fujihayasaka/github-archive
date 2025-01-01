# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class VerifyCreationMetadataTest < GitHub::TestCase
    include CodespacesRepoHelper

    test "updates the OID for all codespaces regardless of how they were created when force-pushed" do
      codespace = create(:codespace, :with_valid_git_repo, oid: SecureRandom.hex(20))
      assert_changes -> { codespace.oid } do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "doesn't update the OID of a codespace that isn't published from a template if not force-pushed" do
      codespace = create(:codespace, :with_valid_git_repo, oid: SecureRandom.hex(20))
      assert_no_changes -> { codespace.oid } do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: false,
        )
      end
    end

    test "doesn't update the OID of a codespace if it's still valid" do
      codespace = create(:codespace, :with_valid_git_repo)
      assert_no_changes -> { codespace.oid } do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "we leave the devcontainer_path unchanged when we don't have to change it" do
      repo = repo_with_devcontainer
      codespace = create(:codespace, repository: repo, oid: SecureRandom.hex(20), devcontainer_path: ".devcontainer/devcontainer.json")
      assert_no_changes -> { codespace.devcontainer_path } do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "we reset to the default devcontainer path if the existing one is invalid" do
      repo = repo_with_devcontainer
      codespace = create(:codespace, repository: repo, ref: "master", oid: SecureRandom.hex(20), devcontainer_path: ".devcontainer/original/devcontainer.json")
      assert_changes -> { codespace.devcontainer_path }, to: ".devcontainer/devcontainer.json" do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "we reset devcontainer_path to nil if we can't find a valid default path" do
      codespace = create(:codespace, :with_valid_git_repo, ref: "master", oid: SecureRandom.hex(20), devcontainer_path: ".devcontainer/original/devcontainer.json")
      assert_changes -> { codespace.devcontainer_path }, to: nil do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "we set devcontainer_path to the default devcontainer path when we don't have one to begin with" do
      repo = repo_with_devcontainer
      codespace = create(:codespace, repository: repo, ref: "master", oid: SecureRandom.hex(20), devcontainer_path: nil)
      assert_changes -> { codespace.devcontainer_path }, to: ".devcontainer/devcontainer.json" do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end

    test "we leave the devcontainer_path alone if we're not modifying the OID" do
      codespace = create(:codespace, :with_valid_git_repo, devcontainer_path: nil)
      assert_no_changes -> { codespace.devcontainer_path } do
        Codespaces::VerifyCreationMetadata.call(
          codespace: codespace,
          force_pushed: true,
        )
      end
    end
  end
end
