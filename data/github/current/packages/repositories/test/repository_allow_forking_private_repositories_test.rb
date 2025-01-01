# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryAllowForkingPrivateRepositoriesTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)

    @repo = create(:repository)

    @org = create(:organization)
    @public_org_repo = create(:repository, owner: @org)
    @private_org_repo = create :private_repository, owner: @org
  end

  test "non-org repositories are forkable by default" do
    assert_predicate @repo, :allow_private_repository_forking?
    refute @repo.allow_private_repository_forking_disabled_by_inherited_policy?
    refute_predicate @repo, :private_repository_forking_configurable?
  end

  test "org public repositories are forced to true even if org setting is false" do
    @org.block_private_repository_forking(actor: @owner)

    assert @public_org_repo.allow_private_repository_forking?
    refute_predicate @public_org_repo, :private_repository_forking_configurable?
  end

  test "org repositories default to false if org setting is default (off)" do
    refute_predicate @private_org_repo, :allow_private_repository_forking?
    assert_predicate @private_org_repo, :allow_private_repository_forking_disabled_by_inherited_policy?
    assert_predicate @private_org_repo, :private_repository_forking_configurable?
  end

  test "org repositories default to true if org setting is on" do
    @org.allow_private_repository_forking(actor: @owner)

    assert_predicate @private_org_repo, :allow_private_repository_forking?
    refute_predicate @private_org_repo, :allow_private_repository_forking_disabled_by_inherited_policy?
    assert_predicate @private_org_repo, :private_repository_forking_configurable?
  end

  test "org repositories can be set to false if org setting is on" do
    @org.allow_private_repository_forking(actor: @owner)
    @private_org_repo.block_private_repository_forking(actor: @owner)

    refute_predicate @private_org_repo, :allow_private_repository_forking?
    refute_predicate @private_org_repo, :allow_private_repository_forking_disabled_by_inherited_policy?
    assert_predicate @private_org_repo, :private_repository_forking_configurable?
  end

  test "org repositories default to false if org setting is off" do
    @org.block_private_repository_forking(actor: @owner)

    refute_predicate @private_org_repo, :allow_private_repository_forking?
    assert_predicate @private_org_repo, :allow_private_repository_forking_disabled_by_inherited_policy?
    assert_predicate @private_org_repo, :private_repository_forking_configurable?
  end

  test "org repositories force to false if org setting is off" do
    @private_org_repo.allow_private_repository_forking(actor: @owner)
    @org.block_private_repository_forking(actor: @owner)

    refute_predicate @private_org_repo, :allow_private_repository_forking?
    assert_predicate @private_org_repo, :allow_private_repository_forking_disabled_by_inherited_policy?
    assert_predicate @private_org_repo, :private_repository_forking_configurable?
  end

  test "forks obey org setting" do
    member = create(:user)
    @org.add_member(member)
    @org.allow_private_repository_forking(actor: @owner)

    fork_repo = create(:fork_repository, forker: member, fork_repo: @private_org_repo)
    assert_predicate fork_repo.reload, :allow_private_repository_forking?

    @org.block_private_repository_forking(actor: @owner)
    refute_predicate fork_repo.reload, :allow_private_repository_forking?
  end
end
