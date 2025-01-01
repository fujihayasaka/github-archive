# typed: true
# frozen_string_literal: true

require "test_helper"

class NavigationRepositoryGraphsViewTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @user = create(:user)
    @random = create(:user, login: "user-random")
    @repo = create(:repository)
    @private_repo = create(:private_repository, owner: @user)
    @fork = fast_fork_repo(@repo, owner: @user)
    @admin = create(:user)
    @repo.add_member_without_validation_or_notifications(@admin, action: :admin)
    @private_repo.add_member_without_validation_or_notifications(@admin, action: :admin)

    @org = create(:business_plus_organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
  end

  context "#show_community?" do
    if GitHub.community_profile_enabled?
      test "returns false for owner viewing private repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @owner, current_repository: @private_repo)
        refute_predicate view, :show_community?
      end

      test "returns false for admin viewing private repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @admin, current_repository: @private_repo)
        refute_predicate view, :show_community?
      end

      test "returns false for non-owner viewing private repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @private_repo)
        refute_predicate view, :show_community?
      end

      test "returns true for non-repo-owner viewing public repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @repo)
        assert view.show_community?
      end

      test "returns false for non-logged-in-user viewing private repository" do
        view = Navigation::Repository::GraphsView.new(current_user: nil, current_repository: @private_repo)
        refute_predicate view, :show_community?
      end

      test "returns true for repo owner viewing public repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @owner, current_repository: @repo)
        assert_predicate view, :show_community?
      end

      test "returns true for repo admin viewing public repository" do
        view = Navigation::Repository::GraphsView.new(current_user: @admin, current_repository: @repo)
        assert_predicate view, :show_community?
      end

      test "returns false for fork" do
        view = Navigation::Repository::GraphsView.new(current_user: @admin, current_repository: @fork)
        refute_predicate view, :show_community?
      end
    else
      test "returns false for non-repo-owner viewing public repository when community profile disabled" do
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @repo)
        refute_predicate view, :show_community?
      end
    end
  end

  context "#show_dependency_graph?" do
    if GitHub.enterprise?
      test "returns false when GitHub.dependency_graph_enabled? is false" do
        GitHub.stubs(
          dependency_graph_enabled?: false,
        )
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @private_repo)
        refute_predicate view, :show_dependency_graph?
      end

      test "returns false when GitHub.dependency_graph_enabled is true but not enabled in enterprise" do
        GitHub.stubs(
          dependency_graph_enabled?: true,
          dotcom_connection_enabled?: false,
          ghe_content_analysis_enabled?: false,
        )
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @private_repo)
        assert_predicate view, :show_dependency_graph?
      end

      test "returns true when all enabled in enterprise" do
        GitHub.stubs(
          dependency_graph_enabled?: true,
          dotcom_connection_enabled?: true,
          ghe_content_analysis_enabled?: true,
        )
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @private_repo)
        assert_predicate view, :show_dependency_graph?
      end
    else
      test "returns true for dotcom" do
        view = Navigation::Repository::GraphsView.new(current_user: @random, current_repository: @private_repo)
        assert_predicate view, :show_dependency_graph?
      end
    end
  end

  context "#show_people?" do
    test "true for org repo with feature enabled and org admin viewer" do
      view = Navigation::Repository::GraphsView.new(current_user: @user, current_repository: @org_repo)
      assert_predicate view, :show_people?
    end

    test "false for org repo for random user" do
      view = Navigation::Repository::GraphsView.new(current_user: create(:user), current_repository: @org_repo)
      refute_predicate view, :show_people?
    end

    test "false for org repo for repo admin who is not org admin" do
      collab = create(:user)
      @org_repo.add_member(collab, action: :admin)
      assert @org_repo.adminable_by?(collab)
      refute @org.adminable_by?(collab)

      view = Navigation::Repository::GraphsView.new(current_user: collab, current_repository: @org_repo)
      refute_predicate view, :show_people?
    end

    test "false for user owned repo" do
      view = Navigation::Repository::GraphsView.new(current_user: @user, current_repository: @repo)
      refute_predicate view, :show_people?
    end
  end
end
