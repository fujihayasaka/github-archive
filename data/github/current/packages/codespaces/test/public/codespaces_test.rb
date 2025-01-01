# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesTest < GitHub::TestCase
  context "#trusted_repository_authorizations_with_repository" do
    test "does not filter out authorizations that have a repository" do
      user = create(:user)
      create(:codespace_trusted_repository_authorization, user: user)
      repository = create(:repository)
      create(:codespace_trusted_repository_authorization, user: user, repository: repository)

      trusted_repository_authorizations = Codespaces.trusted_repository_authorizations_with_repository(user)
      assert_equal 2, trusted_repository_authorizations.size
    end

    test "filters out authorizations that have a nil repository" do
      user = create(:user)
      create(:codespace_trusted_repository_authorization, user: user)
      repository = create(:repository)
      create(:codespace_trusted_repository_authorization, user: user, repository: repository)
      repository.destroy!

      trusted_repository_authorizations = Codespaces.trusted_repository_authorizations_with_repository(user)
      assert_equal 1, trusted_repository_authorizations.size
    end
  end
end unless GitHub.enterprise?
