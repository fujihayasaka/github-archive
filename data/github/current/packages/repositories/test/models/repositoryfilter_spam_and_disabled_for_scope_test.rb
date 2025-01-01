# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryfilterSpamAndDisabledForScopeTest < GitHub::TestCase
  fixtures do
    @staff_admin_user = create(:staff_admin_user)
    @disabled_repo = create(:repository)
    @disabled_repo.access.disable("size", @staff_admin_user)

    @spammer = create(:user, spammy: true)
    @spammy_repo = create(:repository, owner: @spammer)

    @normal_repo = create(:repository)
  end

  test "filters disabled repos if viewer is not staff admin" do
    viewer = create(:user)
    refute_includes Repository.filter_spam_and_disabled_for(viewer), @disabled_repo
  end

  test "keeps disabled repos if viewer is staff admin" do
    viewer = @staff_admin_user
    assert_includes Repository.filter_spam_and_disabled_for(viewer), @disabled_repo
  end

  if GitHub.spamminess_check_enabled?
    test "filters spam repos if the viewer is not staff or the spammer" do
      viewer = create(:user)
      refute_includes Repository.filter_spam_and_disabled_for(viewer), @spammy_repo
    end

    test "keeps spam repos if the viewer is the spammer" do
      viewer = @spammer
      assert_includes Repository.filter_spam_and_disabled_for(viewer), @spammy_repo
    end

    test "keeps spam repos if the viewer is a staff admin" do
      viewer = @staff_admin_user
      assert_includes Repository.filter_spam_and_disabled_for(viewer), @spammy_repo
    end
  end

  test "keeps non-spam, non-disabled repos for random viewer" do
    viewer = create(:user)
    assert_includes Repository.filter_spam_and_disabled_for(viewer), @normal_repo
  end

  test "keeps non-spam, non-disabled repos for anonymous viewer" do
    viewer = nil
    assert_includes Repository.filter_spam_and_disabled_for(viewer), @normal_repo
  end
end
