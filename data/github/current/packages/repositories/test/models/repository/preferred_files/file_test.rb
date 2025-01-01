# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPreferredFilesFileTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @local_repo = create(:repository, owner: @user)
    @global_repo = create(:repository, owner: @user, name: Repository::GLOBAL_HEALTH_FILES_NAME)
    @tree_repo = create(:repository, from_example: :readmes)

    @tree_entry = @tree_repo.preferred_readme.freeze
    @local_funding = create(:repository_preferred_file, :funding,
      repository: @local_repo,
      path: ".github/FUNDING.yml"
    )
    @global_coc = create(:repository_preferred_file,
      filetype: :code_of_conduct,
      repository: @global_repo,
      path: "CODE_OF_CONDUCT.md",
    )
  end

  context ".from_record" do
    test "creates a File object from RepositoryPreferredFile record" do
      file = Repository::PreferredFiles::File.from_record(
        record: @global_coc,
        context_repository: @global_repo,
      )
      assert_equal @global_coc.filetype.to_sym, file.type
      assert_equal @global_coc, file.object
      assert_equal @global_coc.path, file.path
      assert_equal @global_coc.commit_oid, file.commit_oid
      assert_equal @global_coc.repository, file.repository
      assert_predicate file, :cached?
    end
  end

  context ".from_tree_entry" do
    test "creates a File object from TreeEntry" do
      file = Repository::PreferredFiles::File.from_tree_entry(
        type: :readme,
        tree_entry: @tree_entry,
        context_repository: @tree_repo,
      )

      assert_equal :readme, file.type
      assert_equal @tree_entry, file.object
      assert_equal @tree_entry.path, file.path
      assert_equal @tree_entry.repository.default_oid, file.commit_oid
      assert_equal @tree_entry.repository, file.repository
      assert_predicate file, :tree_entry?
    end
  end

  context "#tree_entry" do
    test "returns tree entry for cached result" do
      RepositoryCheckPreferredFilesJob.perform_now(@tree_repo.id, @tree_repo.default_oid)

      file = @tree_repo.preferred_files.fetch(:readme)
      assert_equal :readme, file.type
      assert_predicate file, :cached?
      assert_equal @tree_entry, file.tree_entry
    end

    test "returns tree entry for tree entry result" do
      file = Repository::PreferredFiles::File.from_tree_entry(
        type: :readme,
        tree_entry: @tree_entry,
        context_repository: @tree_repo,
      )

      assert_equal :readme, file.type
      assert_predicate file, :tree_entry?
      assert_equal @tree_entry, file.tree_entry
    end

    test "returns nil if tree entry does not exist" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )

      assert_nil file.tree_entry
    end
  end

  context "#filename" do
    test "returns filename for file in repo root" do
      file = Repository::PreferredFiles::File.from_record(
        record: @global_coc,
        context_repository: @global_repo,
      )
      assert_equal "CODE_OF_CONDUCT.md", file.path
      assert_equal "CODE_OF_CONDUCT.md", file.filename
    end

    test "returns filename for file in .github directory" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )
      assert_equal ".github/FUNDING.yml", file.path
      assert_equal "FUNDING.yml", file.filename
    end
  end

  context "#repository_name" do
    test "returns local repo name for local file" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )
      assert_equal @local_repo.name, file.repository_name
    end

    test "returns global repo name for global file" do
      file = Repository::PreferredFiles::File.from_record(
        record: @global_coc,
        context_repository: @global_repo,
      )
      assert_equal @global_repo.name, file.repository_name
    end

    test "returns global repo name for inherited file" do
      file = Repository::PreferredFiles::File.from_record(
        record: @global_coc,
        context_repository: @local_repo,
      )
      assert_equal @global_repo.name, file.repository_name
    end
  end

  context "#permalink" do
    test "returns the path to a local preferred file" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )
      expected = "/#{@local_repo.nwo}/blob/#{@local_funding.commit_oid}/#{@local_funding.path}"
      assert_equal expected, file.permalink
    end

    test "returns the path to a global preferred file" do
      file = Repository::PreferredFiles::File.from_record(
        record: @global_coc,
        context_repository: @local_repo,
      )
      expected = "/#{@global_repo.nwo}/blob/#{@global_coc.commit_oid}/#{@global_coc.path}"
      assert_equal expected, file.permalink
    end

    test "returns the path for a TreeEntry file" do
      file = Repository::PreferredFiles::File.from_tree_entry(
        type: :readme,
        tree_entry: @tree_entry,
        context_repository: @tree_repo,
      )
      expected = "/#{@tree_repo.nwo}/blob/#{@tree_repo.default_oid}/#{@tree_entry.path}"
      assert_equal expected, file.permalink
    end

    test "returns full URL if include_host is true" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )
      expected = "https://github.com/#{@local_repo.nwo}/blob/#{@local_funding.commit_oid}/#{@local_funding.path}"
      assert_equal expected, file.permalink(include_host: true)
    end

    test "returns url with default branch if use_oid: false" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )
      expected = "/#{@local_repo.nwo}/blob/#{@local_repo.default_branch}/#{@local_funding.path}"
      assert_equal expected, file.permalink(use_oid: false)
    end
  end

  context "#no_files_placeholder?" do
    test "returns true if file type is placeholder type" do
      record = create(:repository_preferred_file, :no_preferred_files)
      file = Repository::PreferredFiles::File.from_record(
        record: record,
        context_repository: record.repository,
      )

      assert_predicate file, :no_files_placeholder?
    end

    test "returns false if file type is not placeholder type" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )

      refute_predicate file, :no_files_placeholder?
    end
  end

  context "#missing_cached_metadata?" do
    test "returns true if committed_at is nil" do
      record = create(:repository_preferred_file, committed_at: nil)
      file = Repository::PreferredFiles::File.from_record(
        record: record,
        context_repository: record.repository,
      )

      assert_predicate file, :missing_cached_metadata?
    end

    test "returns false if committed_at is present" do
      file = Repository::PreferredFiles::File.from_record(
        record: @local_funding,
        context_repository: @local_repo,
      )

      refute_predicate file, :missing_cached_metadata?
    end

    test "returns false if file is not cached" do
      file = Repository::PreferredFiles::File.from_tree_entry(
        type: :readme,
        tree_entry: @tree_entry,
        context_repository: @tree_repo,
      )

      refute_predicate file, :missing_cached_metadata?
    end
  end
end
