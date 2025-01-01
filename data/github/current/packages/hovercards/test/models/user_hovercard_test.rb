# typed: true
# frozen_string_literal: true

require "test_helper"

class UserHovercardTest < GitHub::TestCase
  fixtures do
    @user = create(:user, created_at: 1.year.ago)

    @repo = create(:repository, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)

    @private_repo_owner = create(:user, plan: "silver")
    @private_repo = create(:private_repository, owner: @private_repo_owner)
    @private_issue = create(:issue, repository: @private_repo, user: @private_repo_owner)
  end

  context "for a hovercard with no primary subject" do
    test "returns no contexts" do
      hovercard = UserHovercard.new(@user, nil, viewer: @user)

      assert_empty hovercard.contexts
    end
  end

  context "for a user previewing a sponsorship when their org already sponsors them" do
    # https://github.com/github/sponsors/issues/2054
    test "only includes one 'Your sponsor' context" do
      sponsorable = create(:user, :sponsorable)
      corp_sponsorship = create(:sponsorship, :from_org, sponsorable: sponsorable)
      sponsors_listing = sponsorable.sponsors_listing

      org = corp_sponsorship.sponsor
      org.add_member(sponsorable)
      org.publicize_member(sponsorable)

      hovercard = UserHovercard.new(sponsorable, sponsors_listing, viewer: sponsorable)

      your_sponsor_contexts = hovercard.contexts
        .select { |context| context.is_a?(UserHovercard::Contexts::YourSponsor) }
      assert_equal 1, your_sponsor_contexts.size
      refute_predicate your_sponsor_contexts.first, :corporate_sponsor?
    end
  end if GitHub.sponsors_enabled?

  context "for a hovercard with a primary subject that has parents" do
    test "returns a context for the primary subject, and its parent" do
      hovercard = UserHovercard.new(@user, @issue, viewer: @user)

      assert_equal [@issue, @repo], hovercard.subject_hierarchy
    end
  end

  context "for a hovercard with a primary subject that does not have parents" do
    test "returns a context for just the primary subject" do
      hovercard = UserHovercard.new(@user, @repo, viewer: @user)

      assert_equal [@repo], hovercard.subject_hierarchy
    end
  end

  context "for a hovercard with a primary subject that is private" do
    test "returns no subjects when viewed by others" do
      hovercard = UserHovercard.new(@private_repo_owner, @private_issue, viewer: @user)

      assert_equal [], hovercard.subject_hierarchy
    end

    test "returns the full subject list when viewed by self" do
      hovercard = UserHovercard.new(@private_repo_owner, @private_issue, viewer: @private_repo_owner)

      assert_equal [@private_issue, @private_repo], hovercard.subject_hierarchy
    end
  end

  context "#subject_organization" do
    test "returns nil if there is no subject" do
      hovercard = UserHovercard.new(@user, nil, viewer: @user)

      assert_nil hovercard.subject_organization
    end

    test "returns organization if the subject is an org" do
      org = create(:organization)

      hovercard = UserHovercard.new(@user, org, viewer: @user)

      assert_equal org, hovercard.subject_organization
    end

    test "returns organization if the subject is an org-owned object" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      hovercard = UserHovercard.new(@user, repo, viewer: @user)

      assert_equal org, hovercard.subject_organization
    end
  end
end

class HovercardprefixForTest < GitHub::TestCase
  test "it returns 'org' for an Organization" do
    assert_equal "organization", Hovercard.prefix_for(Organization.new)
  end

  test "it returns 'issue' for an Issue" do
    assert_equal "issue", Hovercard.prefix_for(Issue.new)
  end

  test "it returns 'pr' for a PR" do
    assert_equal "pull_request", Hovercard.prefix_for(PullRequest.new)
  end

  test "it returns 'repository' for a Repository" do
    assert_equal "repository", Hovercard.prefix_for(Repository.new)
  end

  test "it returns nil for any other type" do
    assert_nil Hovercard.prefix_for(User.new)
  end
end
