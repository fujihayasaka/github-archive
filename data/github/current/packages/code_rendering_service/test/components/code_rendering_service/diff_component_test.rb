# typed: true
# frozen_string_literal: true

require "test_helper"

class DiffComponentTest < GitHub::TestCase
  setup do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @org)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.ipynb", "notebook")
      files.add("foo.js", "")
    end
    @blob = @repo.blob(@ref.sha, "foo.ipynb")
    @diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")
  end

  test "base class ensure all methods are defined" do
    renderer = CodeRenderingService::DiffComponent.new(@blob, :diff, @user, @repo, opts: {})
    assert_raises(NotImplementedError) { renderer.supported_views }
    assert_raises(NotImplementedError) { renderer.flagged_features }
    assert_raises(NotImplementedError) { renderer.host_url }
  end
end
