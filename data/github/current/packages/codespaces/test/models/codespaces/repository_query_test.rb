# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::RepositoryQueryTest < GitHub::TestCase

  setup do
    @monalisa = create(:paid_user, name: "monalisa")
    @repo = create(:repository, name: "test-repo", owner: @monalisa)
    @codespace = create(:codespace, repository: @repo, owner: @monalisa)
  end

  context "#visible_repo_ids" do
    test "returns codespaces for public repos but not private repos the user lost access to" do
      owner = create(:user)
      codespace = create(:codespace, repository: @repo, owner: owner)
      codespace_2 = create(:codespace, repository: @repo, owner: owner)
      public_repo = create(:repository)
      other_codespace = create(:codespace, repository: public_repo, owner: owner)

      codespace_repository_ids = owner.codespaces.pluck(:repository_id)
      assert_equal 3, codespace_repository_ids.count
      visible = Codespaces::RepositoryQuery.visible_repo_ids(owner, codespace_repository_ids)
      assert_equal 2, visible.count
      assert_includes visible, codespace.repository_id
      assert_includes visible, other_codespace.repository_id

      @repo.errors.clear

      @repo.toggle_visibility(actor: @monalisa)
      @repo.remove_member(owner)

      visible = Codespaces::RepositoryQuery.visible_repo_ids(owner, codespace_repository_ids)
      assert_equal 1, visible.count
      refute_includes visible, codespace.repository_id
      assert_includes visible, other_codespace.repository_id
    end

    test "doesn't return repository_ids for repositories that have been deleted" do
      codespace_repository_ids = @monalisa.codespaces.pluck(:repository_id)
      visible = Codespaces::RepositoryQuery.visible_repo_ids(@monalisa, codespace_repository_ids)
      assert_equal 1, visible.count
      assert_includes visible, @codespace.repository_id

      @repo.destroy

      visible = Codespaces::RepositoryQuery.visible_repo_ids(@monalisa, codespace_repository_ids)
      assert_equal 0, visible.count
    end
  end
end
