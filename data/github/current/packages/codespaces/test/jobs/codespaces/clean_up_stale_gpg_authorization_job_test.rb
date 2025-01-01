# typed: true
# frozen_string_literal: true

require "test_helper"

class CleanUpStaleGpgAuthorizationJob < GitHub::TestCase
  test "when the repository exists and it is pushable, it noops" do
    user = create(:user)
    repository = create(:repository, owner: user)
    authorization = create(:codespace_trusted_repository_authorization, user: user, repository: repository)

    assert_no_difference "Codespaces::TrustedRepositoryAuthorization.count" do
      Codespaces::CleanUpStaleGpgAuthorizationJob.perform_now(gpg_authorization: authorization)
    end
  end

  test "when the repository no longer exists, it destroys the authorization" do
    user = create(:user)
    repository = create(:repository, owner: user)
    authorization = create(:codespace_trusted_repository_authorization, user: user, repository: repository)
    repository.destroy!

    assert_difference "Codespaces::TrustedRepositoryAuthorization.count", -1 do
      Codespaces::CleanUpStaleGpgAuthorizationJob.perform_now(gpg_authorization: authorization)
    end
  end

  test "when the repository exists but it is still not pushable it destroys the authorization" do
    user = create(:user)
    repository = create(:repository)
    authorization = create(:codespace_trusted_repository_authorization, user: user, repository: repository)

    assert_difference "Codespaces::TrustedRepositoryAuthorization.count", -1 do
      Codespaces::CleanUpStaleGpgAuthorizationJob.perform_now(gpg_authorization: authorization)
    end
  end
end
