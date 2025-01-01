# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUpdaterTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "UserRepoOwner")
    @org = create(:organization, admin: @user, login: "OrgRepoOwner")
    @repo = create(:repository, owner: @user, name: "NeatoRepo")
    @org_repo = create(:repository, owner: @org, name: "SweetoRepo")
  end

  test "errors when your repo is archived" do
    @repo.set_archived
    updater = Repository::Updater.new(@repo, actor: @user, name: "BrandNewNameONo")
    refute updater.update, "should fail to update"
    assert_equal "Repository #{@repo.name_with_owner} cannot be edited at this time.", updater.error
  end

  test "errors when your repo is not writable" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    updater = Repository::Updater.new(@repo, actor: @user, name: "BrandNewNameONo")
    refute updater.update, "should fail to update"
    assert_equal "Repository #{@repo.name_with_owner} cannot be edited at this time.", updater.error
  end

  test "errors when repo fails to update" do
    other_repo = create(:repository, owner: @user)
    updater = Repository::Updater.new(@repo, actor: @user, name: other_repo.name)
    refute updater.update, "should fail to update"
    assert_equal "Name already exists on this account", updater.error
  end

  test "errors when you lack permission to update the specified repo" do
    not_my_repo = create(:repository)
    updater = Repository::Updater.new(not_my_repo, actor: @user, name: "BrandNewNameONo")
    refute updater.update, "should fail to update"
    assert_equal "#{@user} does not have permission to update #{not_my_repo.name_with_owner}.",
      updater.error
  end

  test "errors when user tries to update description or homepage URL but can't edit metadata" do
    Repository.any_instance.stubs(:can_edit_repo_metadata?).returns(false)
    updater = Repository::Updater.new(@org_repo, actor: @user, description: "o nice",
                                      homepage: "https://example.com")
    refute updater.update, "should fail to update"
    assert_equal "#{@user} does not have permission to edit metadata " \
                 "on #{@org_repo.name_with_owner}.", updater.error
  end

  test "errors when homepage too long" do
    repo = create(:repository, owner: @user)
    url = "http://#{"a" * 300}.com"
    updater = Repository::Updater.new(@org_repo, actor: @user, description: "o nice",
                                      homepage: url)
    refute updater.update
    assert_equal "Homepage is too long (maximum is 255 characters)", updater.error
  end

  test "errors when user tries to update wiki setting but lacks that permission" do
    Repository.any_instance.stubs(:can_toggle_wiki?).returns(false)
    updater = Repository::Updater.new(@org_repo, actor: @user, has_wiki: !@org_repo.has_wiki?)
    refute updater.update, "should fail to update"
    assert_equal "#{@user} does not have permission to toggle wikis on " \
                 "#{@org_repo.name_with_owner}.", updater.error
  end

  test "errors when enabling repo project when they can't be enabled" do
    @org.disable_repository_projects(actor: @user)
    @org.disable_organization_projects(actor: @user)
    updater = Repository::Updater.new(@org_repo, actor: @user, has_projects: true)
    refute updater.update, "should fail to update"
    assert_equal "Projects cannot be enabled when the owning organization has projects disabled.",
      updater.error
  end

  context "discussions enablement" do
    test "errors when enabling discussions when lacks permissions" do
      @rando = create(:user)
      updater = Repository::Updater.new(@org_repo, actor: @rando, has_discussions: true)
      refute updater.update, "should fail to update"
      assert_equal "#{@rando} does not have permission to update #{@org_repo.nwo}.", updater.error
    end

    test "enables discussions with a valid user" do
      updater = Repository::Updater.new(@org_repo, actor: @user, has_discussions: true)
      assert updater.update, "should update"
      assert @org_repo.reload.discussions_on?
    end

    test "disables discussions with a valid user" do
      @discussions_repo = create(:repository, owner: @user, has_discussions: true)
      updater = Repository::Updater.new(@discussions_repo, actor: @user, has_discussions: false)
      assert updater.update, "should update"
      refute @discussions_repo.reload.discussions_on?
    end
  end

  context "sponsorships enablement" do
    test "errors when enabling sponsorships when actor lacks permissions" do
      rando = create(:user)

      updater = Repository::Updater.new(@org_repo, actor: rando, has_sponsorships: true)

      refute updater.update, "should fail to update"
      assert_equal "#{rando} does not have permission to update #{@org_repo.nwo}.", updater.error
    end

    test "enables sponsorships with a valid user when Sponsors is enabled" do
      updater = Repository::Updater.new(@org_repo, actor: @user, has_sponsorships: true)

      if GitHub.sponsors_enabled?
        assert updater.update, "should update"
        assert_predicate @org_repo.reload, :repository_funding_links_explicitly_enabled?
      else
        refute updater.update, "should not update"
        refute_predicate @org_repo.reload, :repository_funding_links_explicitly_enabled?
      end
    end

    test "disables sponsorships with a valid user when Sponsors is enabled" do
      funding_links_repo = create(:repository, owner: @user)
      funding_links_repo.enable_repository_funding_links(actor: @user)
      assert_predicate funding_links_repo, :repository_funding_links_explicitly_enabled?

      updater = Repository::Updater.new(funding_links_repo, actor: @user, has_sponsorships: false)

      if GitHub.sponsors_enabled?
        assert updater.update, "should update"
        refute_predicate funding_links_repo.reload, :repository_funding_links_explicitly_enabled?
      else
        refute updater.update, "should not update"
        assert_predicate funding_links_repo.reload, :repository_funding_links_explicitly_enabled?
      end
    end

    test "errors when repository owner is trade restricted" do
      trade_restricted_org = create(:organization, admin: @user)
      trade_restricted_repo = create(:repository, owner: trade_restricted_org)
      trade_restricted_org.create_trade_controls_restriction(type: :full)

      updater = Repository::Updater.new(trade_restricted_repo, actor: @user, has_sponsorships: true)

      refute updater.update, "should not update"
      refute_predicate trade_restricted_repo.reload, :repository_funding_links_explicitly_enabled?
      assert_equal "Repository #{trade_restricted_repo.name_with_owner} cannot be edited at this time.", updater.error
    end
  end
end
