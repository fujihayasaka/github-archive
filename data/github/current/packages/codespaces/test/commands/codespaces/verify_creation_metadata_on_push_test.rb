# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class VerifyCreationMetadataOnPushTest < GitHub::TestCase
    test "we call the verification_command for each related codespace" do
      # This one should be verified since we're on the given repo/branch and owned by the user that did the push.
      codespace = create(:codespace)
      # This one shouldn't be verified since this would be on a different repo etc.
      create(:codespace)
      mock_command = mock("Codespaces::VerifyCreationMetadata")
      mock_command.expects(:call).once.with(codespace: codespace, force_pushed: false)

      Codespaces::VerifyCreationMetadataOnPush.call(repository: codespace.repository, branch_name: codespace.ref, user: codespace.owner, force_pushed: false, verification_command:  mock_command)
    end
  end
end
