# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionsSlugValidatorTest < GitHub::TestCase
  test "disallows reserved words as slugs" do
    slugs = Set.new.merge(%w[admin ci preview])

    RepositoryActions::SlugValidator.stub_const(:RESERVED_SLUGS, slugs) do
      RepositoryActions::SlugValidator::RESERVED_SLUGS.each do |slug|
        action = build(:repository_action, name: slug, state: "listed")

        refute_predicate action, :valid?
        assert_predicate action.errors[:name], :any?, "should disallow slug from reserved list"
      end
    end
  end

  test "disallows slugs that match an existing Marketplace Category" do
    category = create(:marketplace_category, name: "Monitoring")
    action = build(:repository_action, name: category.slug, state: "listed")

    refute_predicate action, :valid?
    assert_predicate action.errors[:name], :any?, "should disallow slug that matches category name"
  end

  test "disallows slugs that match another Users login" do
    other_user = create(:user)
    repo = create(:repository)
    action = build(:repository_action, repository: repo, name: other_user.login, state: "listed")

    refute_predicate action, :valid?
    assert_predicate action.errors[:name], :any?, "should disallow slug that matches another users login"
  end

  test "allows slugs that match User login if owned by the user" do
    user = create(:user)
    repo = create(:repository, owner: user)
    action = create(:repository_action, :listed, repository: repo)

    action.name = user.login

    assert_predicate action, :valid?
    refute_predicate action.errors[:name], :any?, "should allow slug when owned by the matching user"
  end

  test "user match is case-insensitive" do
    user = create(:user, login: "Mixed-Case")
    repo = create(:repository, owner: user)
    action = create(:repository_action, :listed, repository: repo)

    action.name = user.login

    assert_predicate action, :valid?
    refute_predicate action.errors[:name], :any?, "should allow slug when owned by the matching user"
  end

  test "disallows slugs that match another Orgs login" do
    other_org = create(:organization)

    repo = create(:repository)
    action = build(:repository_action, repository: repo, name: other_org.login, state: "listed")

    refute_predicate action, :valid?
    assert_predicate action.errors[:name], :any?, "should disallow slug that matches another orgs login"
  end

  test "allows slugs that match Org login if owned by same Org" do
    org = create(:organization)
    repo = create(:repository, owner: org)
    action = build(:repository_action, repository: repo, name: org.login, state: "listed")

    refute_predicate action.errors[:name], :any?, "should disallow slug that matches another orgs login"
  end

  test "org match is case-insensitive" do
    org = create(:organization, login: "Mixed-Case")
    repo = create(:repository, owner: org)
    action = create(:repository_action, :listed, repository: repo)

    action.name = org.login

    assert_predicate action, :valid?
    refute_predicate action.errors[:name], :any?, "should disallow slug that matches another orgs login"
  end

  test "previously listed Actions are rechecked when name is changed" do
    action = create(:repository_action, :listed)

    action.update(name: "action")

    refute_predicate action, :valid?
    assert_predicate action.errors[:name], :any?, "should disallow slug that matches reserved word list"
  end
end
