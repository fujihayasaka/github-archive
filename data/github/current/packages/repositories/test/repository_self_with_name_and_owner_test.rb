# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositorySelfWithNameAndOwnerTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user)
    @other_user = create(:user)

    @repo = create(:repository, owner: @user)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  test "finds repos by their nwo" do
    assert_equal @repo, Repository.with_name_with_owner("#{@repo.owner.login}/#{@repo.name}")
  end

  test "finds repos by their owner and repo name" do
    assert_equal @repo, Repository.with_name_with_owner(@repo.owner.login, @repo.name)
  end

  test "finds redirected repos when search_redirects is true" do
    @repo.redirect_from_previous_location("#{@other_user.login}/old-repo")
    assert_equal @repo, Repository.with_name_with_owner("#{@other_user.login}/old-repo", nil, search_redirects: true)
  end

  test "does not find redirected repos search_redirects is false" do
    @repo.redirect_from_previous_location("#{@other_user.login}/old-repo")
    assert_nil Repository.with_name_with_owner("#{@other_user.login}/old-repo", nil, search_redirects: false)
  end

  test "returns nil for non 3 byte UTF-8" do
    assert_no_query_warnings do
      assert_query_count 0 do
        assert_nil Repository.with_name_with_owner("#{@repo.owner_display_login}/emoji-🎃")
      end
    end
  end

  test "returns nil for non 3 byte UTF-8 owner" do
    assert_no_query_warnings do
      assert_query_count 0 do
        assert_nil Repository.with_name_with_owner("emoji-🎃/#{@repo.name}")
      end
    end
  end

  test "finds correct repository based on owner display login in multi-tenant mode" do
    on_multi_tenant_enterprise do
      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business
      shortcode = business.shortcode
      repo = create(:repository, owner: user)

      GitHub::CurrentTenant.remove

      assert_nil Repository.with_name_with_owner(nil, repo.name)
      assert_nil Repository.with_name_with_owner("", repo.name)
      assert_nil Repository.with_name_with_owner("mtodd", repo.name)
      assert_equal repo, Repository.with_name_with_owner("mtodd_#{shortcode}", repo.name)

      GitHub::CurrentTenant.set(business)

      assert_nil Repository.with_name_with_owner(nil, repo.name)
      assert_nil Repository.with_name_with_owner("", repo.name)
      assert_equal repo, Repository.with_name_with_owner("mtodd", repo.name)
      assert_equal repo, Repository.with_name_with_owner("mtodd_#{shortcode}", repo.name)
    end
  end

  test "finds correct redirected repository based on owner display login in multi-tenant mode", skip_enterprise: true do
    on_multi_tenant_enterprise do
      user = create(:emu, login: "mtodd")
      business = user.enterprise_managed_business
      shortcode = business.shortcode
      repo = create(:repository, owner: user, name: "engineering")
      old_repo_name = "engineering-old"
      old_repo_nwo = "#{user.login}/#{old_repo_name}"
      repo.redirect_from_previous_location(old_repo_nwo)

      GitHub::CurrentTenant.remove

      assert_nil Repository.with_name_with_owner(nil, old_repo_name, search_redirects: true)
      assert_nil Repository.with_name_with_owner("", old_repo_name, search_redirects: true)
      assert_nil Repository.with_name_with_owner("mtodd", old_repo_name, search_redirects: true)
      assert_equal repo, Repository.with_name_with_owner("mtodd_#{shortcode}", old_repo_name, search_redirects: true)

      GitHub::CurrentTenant.set(business)

      assert_nil Repository.with_name_with_owner(nil, old_repo_name, search_redirects: true)
      assert_nil Repository.with_name_with_owner("", old_repo_name, search_redirects: true)
      assert_equal repo, Repository.with_name_with_owner("mtodd", old_repo_name, search_redirects: true)
      assert_equal repo, Repository.with_name_with_owner("mtodd_#{shortcode}", old_repo_name, search_redirects: true)
    end
  end
end
