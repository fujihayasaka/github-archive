# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class UpdateUserSecretsTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @codespace = create(:codespace)
    end

    context ".perform" do
      test "send updated secrets to vscs" do
        Codespaces::Secret.expects(:assemble).with(@codespace).returns([])

        Codespaces::VscsClient.any_instance.expects(:update_user_secrets).with(@codespace, secrets: []).once
        Codespaces::UpdateUserSecrets.call(codespace: @codespace)
      end

      test "failed secrets requests raises and abort sending secrets to vscs" do
        Codespaces::Secret.expects(:assemble).with(@codespace).raises(Secrets::Error.new("Secrets Error", nil, nil))
        Codespaces::VscsClient.any_instance.expects(:update_user_secrets).never

        assert_raises(Secrets::Error) do
          Codespaces::UpdateUserSecrets.call(codespace: @codespace)
        end
      end

      test "raises an exception if vscs connection times out" do
        Codespaces::Secret.expects(:assemble).with(@codespace).returns([])
        Codespaces::VscsClient.any_instance.stubs(:update_user_secrets).raises(Codespaces::VscsClient::TimeoutError)

        assert_raises Codespaces::UpdateUserSecrets::ConnectionFailed do
          Codespaces::UpdateUserSecrets.call(codespace: @codespace)
        end
      end

      test "raises an exception if vscs connection fail" do
        Codespaces::Secret.expects(:assemble).with(@codespace).returns([])
        Codespaces::VscsClient.any_instance.stubs(:update_user_secrets).raises(Codespaces::VscsClient::ConnectionFailed)

        assert_raises Codespaces::UpdateUserSecrets::ConnectionFailed do
          Codespaces::UpdateUserSecrets.call(codespace: @codespace)
        end
      end

      test "raises an exception if vscs returns a bad response" do
        Codespaces::Secret.expects(:assemble).with(@codespace).returns([])
        Codespaces::VscsClient.any_instance.stubs(:update_user_secrets).raises(Codespaces::VscsClient::BadResponseError.new("BOOM!"))

        assert_raises Codespaces::UpdateUserSecrets::BadResponse do
          Codespaces::UpdateUserSecrets.call(codespace: @codespace)
        end
      end
    end
  end
end
