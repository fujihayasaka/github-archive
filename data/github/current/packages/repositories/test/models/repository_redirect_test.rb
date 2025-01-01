# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRedirectTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @owner = create(:user, login: "owner", plan: GitHub::Plan.find!("medium"))
    @other = create(:user)

    @repo = create(:repository, name: "repo", owner: @owner)
  end

  test "recording a repository redirect" do
    redirect = @repo.redirect_from_previous_location("other/old-repo")
    assert redirect.is_a?(RepositoryRedirect)
    assert_equal "other/old-repo", redirect.repository_name
    assert_equal @repo, redirect.repository
  end

  test "validates it matches an NWO" do
    redirect = @repo.redirect_from_previous_location("foobar")
    assert redirect.is_a?(RepositoryRedirect)
    assert redirect.errors[:repository_name].any?
    assert_nil redirect.id
  end

  test "finding a repository redirect" do
    @repo.redirect_from_previous_location("other/old-repo")
    repo = RepositoryRedirect.find_redirected_repository("other/old-repo")
    assert_equal @repo, repo
  end

  test "finding a repository redirect with invalid bytes" do
    assert_nil RepositoryRedirect.find_redirected_repository(String.new("foo\x80/bar\x80", encoding: ::Encoding::UTF_8))
    assert_nil RepositoryRedirect.find_redirected_repository("not\u{D0FDE}valid/bar")
  end

  test "finding a redirect uses the most recent" do
    other = create(:repository)

    # prevent indeterminate ordering when created_at is the same
    Timecop.freeze(5.minutes.ago) do
      other.redirect_from_previous_location("other/old-repo")
    end
    @repo.redirect_from_previous_location("other/old-repo")

    assert_equal @repo, RepositoryRedirect.find_redirected_repository("other/old-repo")
  end

  test "finding a repository redirect with different case" do
    @repo.redirect_from_previous_location("Other/Old-Repo")
    repo = RepositoryRedirect.find_redirected_repository("OTHER/OLD-REPO")
    assert_equal @repo, repo
  end

  test "finding a transferred repository by old owner and network" do
    @repo.redirect_from_previous_location("other/old-repo")
    repo = RepositoryRedirect.find_networked_by_old_owner("other", @repo)
    assert_equal @repo, repo
  end

  test "finding a transferred repository by old owner and network is correctly scoped to owner" do
    @repo.redirect_from_previous_location("other/old-repo")
    repo = RepositoryRedirect.find_networked_by_old_owner("oth", @repo)
    assert_nil repo
  end

  test "returns nil when searching for a nil repository name" do
    assert_nil RepositoryRedirect.find_redirected_repository(nil)
  end

  test "returns nil when searching for a blank repository name" do
    assert_nil RepositoryRedirect.find_redirected_repository("")
  end

  test "returns nil if shortcode not included for EMUs", skip_enterprise: true do
    @emu = create :emu, login: "gary"
    @business = @emu.enterprise_managed_business
    @repo = create :repository, name: "repo", owner: @emu
    @repo.redirect_from_previous_location("#{@emu.login}/old-repo")

    assert_nil RepositoryRedirect.find_redirected_repository("gary/old-repo")
  end

  test "is deleted with repository" do
    other_repo = create(:repository)
    other_redirect = other_repo.redirect_from_previous_location("other/old-repo")
    redirect = @repo.redirect_from_previous_location("repo/old-repo")

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [redirect]
      config.expect_not_destroyed = [other_redirect]
    end
  end
end

class RepositoryRedirectMultiTenantTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    on_multi_tenant_enterprise do
      @emu = create :emu, login: "gary"
      @business = @emu.enterprise_managed_business
      @repo = create :repository, name: "repo", owner: @emu
      @repo.redirect_from_previous_location("#{@emu.login}/old-repo")
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  test "finds repo when searching with display_login" do
    repo = RepositoryRedirect.find_redirected_repository("#{@emu.display_login}/old-repo")
    assert_equal @repo, repo
  end

  test "finds repo when searching with suffixed login" do
    repo = RepositoryRedirect.find_redirected_repository("#{@emu.login}/old-repo")
    assert_equal @repo, repo
  end

  test "does not find redirected repo for other business" do
    @business2 = create :business, :enterprise_managed
    GitHub::CurrentTenant.set(@business2)
    @emu2 = create :emu, login: "gary"

    GitHub::CurrentTenant.set(@business2)

    assert_nil RepositoryRedirect.find_redirected_repository("#{@emu.login}/old-repo")
    assert_nil RepositoryRedirect.find_redirected_repository("#{@emu.display_login}/old-repo")
  end
end
