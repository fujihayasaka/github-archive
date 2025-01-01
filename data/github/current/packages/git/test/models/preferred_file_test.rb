# typed: true
# frozen_string_literal: true

require "test_helper"

class PreferredFilevalidPathTest < GitHub::TestCase
  test "returns true for a path in the root" do
    assert PreferredFile.valid_path?(type: :readme, path: "README.md")
  end

  test "returns true for a path under .github" do
    assert PreferredFile.valid_path?(type: :readme, path: ".github/README.md")
  end

  test "returns true for a path under docs" do
    assert PreferredFile.valid_path?(type: :readme, path: "docs/README.md")
  end

  test "returns false for an empty path" do
    refute PreferredFile.valid_path?(type: :readme, path: "")
  end

  test "returns false for a path that looks right-ish" do
    refute PreferredFile.valid_path?(type: :readme, path: "agithub/README.md")
  end

  test "returns false for a path that doesn't match the given type" do
    refute PreferredFile.valid_path?(type: :readme, path: "CONTRIBUTING.md")
  end

  test "returns false for a path point past a valid type" do
    refute PreferredFile.valid_path?(type: :readme, path: "README.md/whoops")
  end
end

class PreferredFilefindTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @empty_repo = create(:repository)
    @valid_root_citation_files = ["CITATION.md", "citations.md", "Citation.bib", "CITATIONS.bib", "CITATION", "citations", "CITATION.cff"]
  end

  setup do
    example_repo :readmes, @repo
    example_repo :readme_none, @empty_repo
    @directory = @repo.directory("master")
  end

  context "boundary cases" do
    test "missing a directory returns nil" do
      assert_nil PreferredFile.find(directory: nil, type: :readme)
    end

    test "given an unknown type raises an error" do
      assert_raises ArgumentError do
        PreferredFile.find(directory: @directory, type: :junk)
      end
    end
  end

  context "preferred files in the root directory" do
    PreferredFile::TYPES.each do |file|
      test "detects #{file} files in the root folder" do
        ref  = @empty_repo.heads.find("master")
        user = @empty_repo.owner
        metadata = { committer: user }
        metadata[:message] = "add #{file} file"
        if file == :citation
          @valid_root_citation_files.each do |citation_file|
            path = citation_file
            temp_append_commit = ref.append_commit(metadata, user) do |files|
              files.add(path, "some content")
            end
            directory = @empty_repo.directory("master")

            preferred_file = PreferredFile.find(directory: directory, type: file)
            assert preferred_file
            assert_equal path, preferred_file.path
            ref.revert_commit(user, temp_append_commit.oid)
          end
        else
          path = case file
          when :repository_task_list
            "tasks.yml"
          when :repository_hubot_task_list
            "hubot.yml"
          when :dashboard
            User::ProfileNavigationDependency::DASHBOARD_FILE_NAME
          when :commands
            "__commands.json"
          when :funding
            "FUNDING.yml"
          when :token_scanning_configuration
            TokenScanningConfigurationFile::DEFAULT_NAME
          else
            file.to_s
          end

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_file = PreferredFile.find(directory: directory, type: file)
          assert preferred_file
          assert_equal path, preferred_file.path
        end
      end
    end
  end

  context "preferred files in subdirectories" do
    PreferredFile::TYPES.each do |file|
      [".github", "docs"].each do |folder|
        case file
        when :citation, :license
          test "doesn't detect #{file} files in the #{folder} folder" do
            ref  = @empty_repo.heads.find("master")
            user = @empty_repo.owner
            metadata = { committer: user }
            metadata[:message] = "add #{file} file"

            file_name = file == :citation ? "CITATION.cff" : "LICENSE.md"
            path = File.join(folder, file_name)

            ref.append_commit(metadata, user) do |files|
              files.add(path, "some content")
            end
            directory = @empty_repo.directory("master")

            preferred_file = PreferredFile.find(directory: directory, type: file)
            refute preferred_file
          end
        else
          test "detects #{file} files in the #{folder} folder" do
            ref  = @empty_repo.heads.find("master")
            user = @empty_repo.owner
            metadata = { committer: user }
            metadata[:message] = "add #{file} file"

            path = case file
            when :repository_task_list
              File.join(folder, "tasks.yml")
            when :repository_hubot_task_list
              File.join(folder, "hubot.yml")
            when :dashboard
              File.join(folder, User::ProfileNavigationDependency::DASHBOARD_FILE_NAME)
            when :commands
              File.join(folder, "__commands.json")
            when :funding
              File.join(folder, "FUNDING.yml")
            when :token_scanning_configuration
              File.join(folder, TokenScanningConfigurationFile::DEFAULT_NAME)
            else
              File.join(folder, file.to_s)
            end

            ref.append_commit(metadata, user) do |files|
              files.add(path, "some content")
            end
            directory = @empty_repo.directory("master")

            preferred_file = PreferredFile.find(directory: directory, type: file)
            assert preferred_file
            assert_equal path, preferred_file.path
          end
        end
      end
    end

    test "also finds FUNDING.yaml" do
      ref  = @empty_repo.heads.find("master")
      user = @empty_repo.owner
      metadata = { committer: user }
      metadata[:message] = "add FUNDING.yaml file"

      ref.append_commit(metadata, user) do |files|
        files.add(".github/FUNDING.yaml", "some content")
      end
      directory = @empty_repo.directory("master")

      preferred_file = PreferredFile.find(directory: directory, type: :funding)
      assert preferred_file
      assert_equal ".github/FUNDING.yaml", preferred_file.path
    end

    test "finds citation file at inst/CITATION" do
      ref  = @empty_repo.heads.find("master")
      user = @empty_repo.owner
      metadata = { committer: user }
      folder = "inst"
      path = "CITATION"
      metadata[:message] = "add #{folder}}/#{path} file"
      File.join(folder, path)
      ref.append_commit(metadata, user) do |files|
        files.add(path, "some content")
      end
      directory = @empty_repo.directory("master")

      preferred_file = PreferredFile.find(directory: directory, type: :citation)
      assert preferred_file
      assert_equal path, preferred_file.path
    end

    test "prefers CITATION.cff over other valid citation files" do
      ref  = @empty_repo.heads.find("master")
      user = @empty_repo.owner
      metadata = { committer: user }

      folder = "inst"
      path_inst = "CITATION"
      metadata[:message] = "add #{folder}}/#{path_inst} file"
      File.join(folder, path_inst)
      ref.append_commit(metadata, user) do |files|
        files.add(path_inst, "some content")
      end

      path_cff = "CITATION.cff"
      metadata[:message] = "add #{path_cff} file"
      File.join(folder, path_cff)
      ref.append_commit(metadata, user) do |files|
        files.add(path_cff, "some content")
      end

      path_md = "CITATION.md"
      metadata[:message] = "add #{path_md} file"
      File.join(folder, path_md)
      ref.append_commit(metadata, user) do |files|
        files.add(path_md, "some content")
      end

      path_bib = "CITATION.bib"
      metadata[:message] = "add #{path_bib} file"
      File.join(folder, path_bib)
      ref.append_commit(metadata, user) do |files|
        files.add(path_bib, "some content")
      end

      path_no_ext = "CITATION"
      metadata[:message] = "add #{path_no_ext} file"
      File.join(folder, path_no_ext)
      ref.append_commit(metadata, user) do |files|
        files.add(path_no_ext, "some content")
      end

      directory = @empty_repo.directory("master")

      preferred_file = PreferredFile.find(directory: directory, type: :citation)
      assert preferred_file
      assert_equal path_cff, preferred_file.path
    end

    test "prefers files in root over docs" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add subfolder README file"

      ref.append_commit(metadata, user) do |files|
        files.add("docs/README.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme)
      assert_equal "README.md", preferred_file.path
    end

    test "finds files with alternate casing" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "rename README.md"

      ref.append_commit(metadata, user) do |files|
        files.move("README.md", "readme.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme)
      assert_equal "readme.md", preferred_file.path
    end

    test "prefers files in .github over root" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add .github README file"

      ref.append_commit(metadata, user) do |files|
        files.add(".github/README.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme)
      assert_equal ".github/README.md", preferred_file.path
    end

    test "prefers files in docs over root if subdirectories passed in" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add subfolder README file"

      ref.append_commit(metadata, user) do |files|
        files.add("docs/README.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme, subdirectories: ["docs"])
      refute_equal "README.md", preferred_file.path
      assert_equal "docs/README.md", preferred_file.path
    end

    test "if subdirectories passed in for docs does not find files in .github or root" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add subfolder README file"

      ref.append_commit(metadata, user) do |files|
        files.add(".github/README.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme, subdirectories: ["docs"])

      assert_nil preferred_file
    end

    test "prefers formatted files over plaintext" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add plaintext README file"

      ref.append_commit(metadata, user) do |files|
        files.add("README.txt", "some plain content")
      end

      directory = @repo.directory("master")
      preferred_file = PreferredFile.find(directory: directory, type: :readme)
      assert_equal "README.md", preferred_file.path
    end
  end

  context "user-specified files in preferred subdirectories" do
    context "with non-allowed types" do
      (PreferredFile::TYPES - PreferredFile::SUBDIRECTORY_TYPES).each do |type|
        test "#{type} raises an error" do
          assert_raises ArgumentError do
            PreferredFile.find(
              directory: @directory,
              type: type,
              nested_filename: "foo.md",
            )
          end
        end
      end
    end

    context "allowed types" do
      PreferredFile::SUBDIRECTORY_TYPES.each do |type|
        test "detects #{type} files in the root folder" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add #{type} file"

          path = File.join(type.to_s.upcase, "foo.md")

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "foo.md",
          )
          assert preferred_file
          assert_equal path, preferred_file.path
        end

        [".github", "docs"].each do |folder|
          test "detects #{type} files in the #{folder} folder" do
            ref  = @empty_repo.heads.find("master")
            user = @empty_repo.owner
            metadata = { committer: user }
            metadata[:message] = "add #{type} file"

            path = File.join(folder, type.to_s.upcase, "foo.md")

            ref.append_commit(metadata, user) do |files|
              files.add(path, "some content")
            end
            directory = @empty_repo.directory("master")

            preferred_file = PreferredFile.find(
              directory: directory,
              type: type,
              nested_filename: "foo.md",
            )
            assert preferred_file
            assert_equal path, preferred_file.path
          end
        end

        test "prefers #{type} files in root over docs" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add #{type} file"

          path = File.join(type.to_s.upcase, "template.md")

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
            files.add(File.join("docs", path), "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "template.md",
          )
          assert_equal path, preferred_file.path
        end

        test "prefers #{type} files in .github over root" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add #{type} file"

          path = File.join(type.to_s.upcase, "template.md")

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
            files.add(File.join(".github", path), "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "template.md",
          )
          assert_equal File.join(".github", path), preferred_file.path
        end

        test "allows the #{type} subdirectory to be pluralized" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add #{type} file"

          path = File.join(type.to_s.pluralize.upcase, "foo.md")

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "foo.md",
          )
          assert preferred_file
          assert_equal path, preferred_file.path
        end

        test "finds exact name matches for #{type} files" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add plaintext template file"

          ref.append_commit(metadata, user) do |files|
            files.add(File.join(type.to_s.upcase, "template.txt"), "some plain content")
            files.add(File.join(type.to_s.upcase, "template.md"), "some formatted content")
          end

          directory = @empty_repo.directory("master")
          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "template.txt",
          )
          assert_equal File.join(type.to_s.upcase, "template.txt"), preferred_file.path
        end

        test "finds non-UTF-8 encoded #{type} file names" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add plaintext template file"

          file_name = "😊template.md".b
          ref.append_commit(metadata, user) do |files|
            files.add(File.join(type.to_s.upcase, file_name), "some formatted content")
          end

          directory = @empty_repo.directory("master")
          preferred_file = PreferredFile.find(
            directory: directory,
            type: type,
            nested_filename: "😊template.md",
          )
          assert_equal File.join(type.to_s.upcase, file_name), preferred_file.path
        end
      end
    end
  end
end

class PreferredFilefindallTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @empty_repo = create(:repository)
  end

  setup do
    example_repo :readmes, @repo
    example_repo :readme_none, @empty_repo
    @directory = @repo.directory("master")
  end

  context "boundary cases" do
    test "missing a directory returns nil" do
      assert_empty PreferredFile.find_all(directory: nil, type: :pull_request_template)
    end

    test "raises an error for unsupported type" do
      assert_raises ArgumentError do
        PreferredFile.find_all(directory: @directory, type: :readme)
      end
    end
  end

  context "preferred files in the root directory" do
    PreferredFile::SUBDIRECTORY_TYPES.each do |file|
      test "detects #{file} files in the root folder" do
        ref  = @empty_repo.heads.find("master")
        user = @empty_repo.owner
        metadata = { committer: user }
        metadata[:message] = "add #{file} file"
        path = "#{file}.md"

        ref.append_commit(metadata, user) do |files|
          files.add(path, "some content")
        end
        directory = @empty_repo.directory("master")

        preferred_files = PreferredFile.find_all(directory: directory, type: file)
        assert_equal [path], preferred_files.map(&:path)
      end
    end
  end

  context "preferred files in subdirectories" do
    PreferredFile::SUBDIRECTORY_TYPES.each do |file|
      [".github", "docs"].each do |folder|
        test "detects #{file} files in the #{folder} folder" do
          ref  = @empty_repo.heads.find("master")
          user = @empty_repo.owner
          metadata = { committer: user }
          metadata[:message] = "add #{file} file"

          path = File.join(folder, "#{file}.md")

          ref.append_commit(metadata, user) do |files|
            files.add(path, "some content")
          end
          directory = @empty_repo.directory("master")

          preferred_files = PreferredFile.find_all(directory: directory, type: file)
          assert_equal [path], preferred_files.map(&:path)
        end
      end
    end

    test "finds all files for a particular type" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add subfolder PULL_REQUEST_TEMPLATE file"

      ref.append_commit(metadata, user) do |files|
        files.add("PULL_REQUEST_TEMPLATE.md", "some content")
        files.add("PULL_REQUEST_TEMPLATE/custom.md", "some content")
      end

      directory = @repo.directory("master")
      preferred_files = PreferredFile.find_all(directory: directory, type: :pull_request_template)
      assert_same_elements %w(PULL_REQUEST_TEMPLATE.md PULL_REQUEST_TEMPLATE/custom.md), preferred_files.map(&:path)
    end

    test "if subdirectories passed in for docs does not find files in .github or root" do
      ref  = @repo.heads.find("master")
      user = @repo.owner
      metadata = { committer: user }
      metadata[:message] = "add subfolder ISSUE_TEMPLATE file"

      ref.append_commit(metadata, user) do |files|
        files.add(".github/ISSUE_TEMPLATE.md", "some content")
      end

      directory = @repo.directory("master")
      assert_empty PreferredFile.find_all(directory: directory, type: :issue_template, subdirectories: ["docs"])
    end
  end
end
