# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FindAffectedCodespacesByUserTest < GitHub::TestCase
  fixtures do
    @codespace = create(:codespace)
    @unrelated_codespace = create(:codespace)
  end

  context "#call" do
    test "processes system events for found codespaces" do
      refute_equal @codespace.owner.id, @unrelated_codespace.owner.id
      CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [@codespace], deletion_reason: nil)
      Codespaces::FindAffectedCodespacesByUser.new(user_id: @codespace.owner.id).call
    end
  end
end
