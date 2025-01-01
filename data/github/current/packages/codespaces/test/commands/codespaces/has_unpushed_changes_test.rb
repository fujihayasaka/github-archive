# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class HasUnpushedChangesTest < GitHub::TestCase

    test "returns `false` when provided a codespace that is not yet provisioned" do
      unprovisioned = create(:codespace, :unprovisioned)

      refute Codespaces::HasUnpushedChanges.call(codespace: unprovisioned, user: unprovisioned.owner)
    end

    test "returns `false` when provided a codespace with a missing VSCS environment" do
      codespace = create(:codespace)
      FakeVSOServer.environments = []

      refute Codespaces::HasUnpushedChanges.call(codespace: codespace, user: codespace.owner)
    end

    test "returns the value from VSCO" do
      codespace = create(:codespace)
      FakeVSOServer.environments = [
        {
          "id" => codespace.guid,
          # Rest of the payload is irrelevant.
          "hasUnpushedGitChanges" => true
        }
      ]

      assert Codespaces::HasUnpushedChanges.call(codespace: codespace, user: codespace.owner)
    end
  end
end
