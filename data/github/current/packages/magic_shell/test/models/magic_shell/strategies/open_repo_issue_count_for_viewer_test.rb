# typed: true
# frozen_string_literal: true

require "test_helper"

class MagicShell::Strategies::OpenRepoIssueCountForViewerTest < GitHub::TestCase

  skip_enterprise

  fixtures do
    @pub_user  = create(:user)

    @pub_repo   = create(:repository, owner: @pub_user,  pushed_at: Time.now - 2.hours, from_example: :mojombo_grit)
  end

  setup do
    @strategy = MagicShell::Strategies::OpenRepoIssueCountForViewer.new
  end

  context "can_use_precomputed_data?" do
    test "is true with no viewer" do
      assert_equal true, @strategy.can_use_precomputed_data?(nil, @pub_repo)
    end

    test "is true with a regular non-owning user" do
      assert_equal true, @strategy.can_use_precomputed_data?(create(:user), @pub_repo)
    end

    test "is false when user is the owner" do
      assert_equal false, @strategy.can_use_precomputed_data?(@pub_user, @pub_repo)
    end

    test "is false when user spammy" do
      spammy_user = create(:user, spammy: true)
      assert_equal false, @strategy.can_use_precomputed_data?(spammy_user, @pub_repo)
    end

    test "is false when user is an admin" do
      admin_user = create(:staff_admin_user)
      assert_equal false, @strategy.can_use_precomputed_data?(admin_user, @pub_repo)
    end
  end
end
