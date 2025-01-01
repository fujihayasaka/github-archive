# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersProjectFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "org-owner")
    @org = create(:organization, admin: @user)
    @org_project = create(:project, owner: @org)
    @user_project = create(:project, owner: @user)
    @private_org_repo = create(:private_repository, owner: @org)
    @private_org_repo_project = create(:project, owner: @private_org_repo)
  end

  setup do
    @org_quals = Search::ParsedQuery.qualifiers
    @org_quals[:user].must(@org.login)

    @user_quals = Search::ParsedQuery.qualifiers
    @user_quals[:user].must(@user.login)
  end

  def oauthed_user(user = create(:user), scopes = [])
    User.with_oauth_hashed_token(make_oauth(user, scopes).hashed_token)
  end

  context "without a current user" do
    test "creates a public-only filter for orgs" do
      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: nil, qualifiers: @org_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "creates a public-only filter for users" do
      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: nil, qualifiers: @user_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end
  end

  context "with a current user" do
    test "cannot view private org projects that the current user has no access on" do
      collab = create(:user, login: "collab")
      @org_project.update(public: false)

      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: collab, qualifiers: @org_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "cannot view private user projects that the current user has no access on" do
      collab = create(:user, login: "collab")
      @user_project.update(public: false)

      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: collab, qualifiers: @user_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "can view private org projects that the current user has read access on" do
      collab = create(:user, login: "collab")
      @org_project.update(public: false)
      @org_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: collab, qualifiers: @org_quals)

      expected = {
        bool: {
          should: [
            { term: { public: true } },
            { term: { _id: @org_project.id } },
          ],
        },
      }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "can view private user projects that the current user has read access on" do
      collab = create(:user, login: "collab")
      @user_project.update(public: false)
      @user_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: collab, qualifiers: @user_quals)

      expected = {
        bool: {
          should: [
            { term: { public: true } },
            { term: { _id: @user_project.id } },
          ],
        },
      }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end
  end

  context "with a current oauthed user with repo scope" do
    test "cannot view private org projects that the current user has no access on" do
      collab = create(:user, login: "collab")
      @org_project.update(public: false)

      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: oauthed_user(collab, ["repo"]), qualifiers: @org_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "cannot view private user projects that the current user has no access on" do
      collab = create(:user, login: "collab")
      @user_project.update(public: false)

      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: oauthed_user(collab, ["repo"]), qualifiers: @user_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "can view private org projects that the current user has read access on" do
      collab = create(:user, login: "collab")
      @org_project.update(public: false)
      @org_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: oauthed_user(collab, ["repo"]), qualifiers: @org_quals)

      expected = {
        bool: {
          should: [
            { term: { public: true } },
            { term: { _id: @org_project.id } },
          ],
        },
      }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    context "scoped" do
      test "can view private org repo projects that the current user has read access on" do
        # Create a bunch of extra projects in private repos, so we can assert there are no `n+1`s
        extra_project_ids = Array.new(3).map do
          private_org_repo = create(:private_repository, owner: @org)
          private_org_repo_project = create(:project, owner: private_org_repo)
          private_org_repo_project.id
        end

        # assert there are no `n+1`s
        filter = assert_query_count_per_table({ projects: 2, repositories: 1 }) do
          Search::Filters::ProjectFilter.new(
            owner_id: @org.id,
            current_user: @user,
            scoped: true,
            qualifiers: @org_quals
          )
        end

        expected = {
          bool: {
            should: [
              { term: { public: true } },
              { terms: { _id: [@org_project.id, @private_org_repo_project.id] + extra_project_ids } },
            ],
          },
        }

        assert_equal expected[:bool][:should][0], filter.must[:bool][:should][0]
        assert_same_elements expected[:bool][:should][1][:terms][:_id], filter.must[:bool][:should][1][:terms][:_id]
        assert_predicate filter, :valid?
        refute_predicate filter, :blank?
      end
    end

    test "can view private user projects that the current user has read access on" do
      collab = create(:user, login: "collab")
      @user_project.update(public: false)
      @user_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: oauthed_user(collab, ["repo"]), qualifiers: @user_quals)

      expected = {
        bool: {
          should: [
            { term: { public: true } },
            { term: { _id: @user_project.id } },
          ],
        },
      }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end
  end

  context "with a current oauthed user without repo scope" do
    test "cannot view private org projects" do
      collab = create(:user, login: "collab")
      @org_project.update(public: false)
      @org_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @org.id, current_user: oauthed_user(collab), qualifiers: @org_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end

    test "cannot view private user projects" do
      collab = create(:user, login: "collab")
      @user_project.update(public: false)
      @user_project.update_user_permission(collab, :read)

      filter = Search::Filters::ProjectFilter.new(owner_id: @user.id, current_user: oauthed_user(collab), qualifiers: @user_quals)
      expected = { term: { public: true } }

      assert_equal expected, filter.must
      assert_predicate filter, :valid?
      refute_predicate filter, :blank?
    end
  end
end
