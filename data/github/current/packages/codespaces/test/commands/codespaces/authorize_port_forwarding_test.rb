# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class AuthorizePortForwardingTest < GitHub::TestCase
    setup do
      skip if GitHub.enterprise?
    end

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user)
      @codespace = create(:codespace, owner: @user, repository: @repo)
    end

    context "scope" do
      test "returns org scope" do
        _, scope = Codespaces::AuthorizePortForwarding.call(
          user: @user,
          codespace: @codespace,
          visibility: Codespaces::AuthorizePortForwarding::VISIBILITY_ORG,
        )
        assert_equal scope, Codespaces::VscsClient::ORG_SCOPE
      end
      test "returns private scope if visibility is nil" do
        _, scope = Codespaces::AuthorizePortForwarding.call(
          user: @user,
          codespace: @codespace,
          visibility: nil,
        )
        assert_equal scope, Codespaces::VscsClient::PRIVATE_SCOPE
      end

      test "returns false if repo is nil" do
        @codespace.repository.destroy!
        @codespace.reload
        assert_nil @codespace.repository
        accessible, _ = Codespaces::AuthorizePortForwarding.call(
          user: @user,
          codespace: @codespace,
          visibility: nil,
        )
        assert_equal accessible, false
      end
    end
  end
end
