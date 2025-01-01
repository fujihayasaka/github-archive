# typed: true
# frozen_string_literal: true

require "test_helper"

class RefCreateCommitTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :mojombo_grit)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @ref = @repo.heads.find("master")
  end

  def valid_params
    {
      changes: [
        { path: "simpson/homer", content: "springfield" },
        { deletion: true, path: "History.txt" },
        { path: "README.txt", content: "hello world", new_path: "hello.txt" },
        { path: "Rakefile", new_path: "rake_file" },
      ],
      headline: "lotta changes",
      author: @repo.owner,
      body: "explanation",
    }
  end

  test "appends a commit with all requested changes" do
    @ref.create_commit(**valid_params)

    commit = @ref.target
    assert_equal "lotta changes\n\nexplanation", commit.message
    assert_equal @repo.owner, commit.author

    assert_equal "springfield\n", @repo.blob(commit.oid, "simpson/homer").data

    assert_nil @repo.blob(commit.oid, "History.txt")

    assert_nil @repo.blob(commit.oid, "README.txt")
    assert_equal "hello world\n", @repo.blob(commit.oid, "hello.txt").data

    assert_nil @repo.blob(commit.oid, "Rakefile")
    assert_equal @repo.blob(commit.parent_oids.first, "Rakefile").data, @repo.blob(commit.oid, "rake_file").data
  end

  test "fails when rando tries to push without having write permission" do
    rando = create(:user)
    params = valid_params.merge(author: rando)
    ex = assert_raises(Git::Ref::UpdateFailed) { @ref.create_commit(**params) }
    assert_equal "Cannot write to repository.", ex.message
  end

  test "fails when attempting to push to protected branch" do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
      creator: @repo.owner,
      pull_request_reviews_enforcement_level: :everyone,
    )
    ex = assert_raises(Git::Ref::ProtectedBranchUpdateError) { @ref.create_commit(**valid_params) }
  end

  test "preserves content line endings" do
    flavours = %w(chocolate vanilla strawberry)
    @ref.append_commit({ message: "more stuff", author: @repo.owner }, @repo.owner) do |files|
      files.add("ice-cream", flavours.join("\n"))
      files.add("ice-cream-crlf", flavours.join("\r\n"))
    end

    flavours << "cookie-dough"
    content = [
      { path: "ice-cream", content: flavours.join("\r\n") },
      { path: "ice-cream-crlf", content: flavours.join("\r\n") },
    ]
    params = valid_params.merge(changes: content)
    @ref.create_commit(**params)

    content = @repo.blob(@ref.target_oid, "ice-cream").data
    assert_equal flavours.join("\n") + "\n", content

    content = @repo.blob(@ref.target_oid, "ice-cream-crlf").data
    assert_equal flavours.join("\r\n") + "\r\n", content
  end

  test "deletion is highest precedence" do
    params = valid_params.merge(changes: [{ deletion: true, path: "README.txt", content: "new content", new_path: "content.txt" }])
    @ref.create_commit(**params)

    assert_nil @repo.blob(@ref.target_oid, "README.txt")
    assert_nil @repo.blob(@ref.target_oid, "content.txt")
  end
end
