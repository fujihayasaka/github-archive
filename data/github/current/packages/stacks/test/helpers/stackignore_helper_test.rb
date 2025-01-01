# typed: true
# frozen_string_literal: true

require "test_helper"

# Code referred from test/helpers/stacks_clone_helper_test.rb
class StackignoreHelperTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @target_repo = create(:repository, name: "Stack instance repo")
  end

  test "ignore .github/stacks folder if no .stackignore present" do
    file_list = [
      ".github/stacks/file2.txt",
      ".github/stacks/folder1/file.txt",
      ".github/stacks/folder1/folder2/file.txt",
      "file.txt",
    ]

    expected_file_list = [
      "file.txt"
    ]

    oid = create_repo_with_files(file_list)
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "ignore README.md file if no .stackignore present" do
    file_list = [
      "README.md",
      "file.txt",
    ]

    expected_file_list = [
      "file.txt"
    ]

    oid = create_repo_with_files(file_list)
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "ignore .stackignore file " do
    file_list = [
      "folder/file2.txt",
      "file1.txt"
    ]

    expected_file_list = [
      "folder/file2.txt",
      "file1.txt"
    ]

    oid = create_repo_with_files(file_list, "# Empty stack ignore file\n#This is an empty .stackignorefile")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "ignore .stackignore, README.md and .github/stacks folder" do
    file_list = [
      ".github/stacks/file2.txt",
      ".github/stacks/folder1/file.txt",
      ".github/stacks/folder1/folder2/file.txt",
      "README.md",
      "file.txt",
    ]

    expected_file_list = [
      "file.txt"
    ]

    oid = create_repo_with_files(file_list, "# Empty stack ignore file\n#This is an empty .stackignorefile")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "ignore should be case-sensitive" do
    file_list = [
      "folder/FILE1.txt",
      "file1.txt",
      "Folder/file1.txt",
      "FOLDER2/File1.TXT"
    ]

    expected_file_list = [
      "folder/FILE1.txt",
      "FOLDER2/File1.TXT"
    ]

    oid = create_repo_with_files(file_list, "file1.txt")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "Comments in .stackignore should be ignored" do
    file_list = [
      "file1.txt",
      "file2.txt",
      "file3.txt"
    ]

    expected_file_list = [
      "file2.txt",
      "file3.txt"
    ]

    oid = create_repo_with_files(file_list, "file1.txt\n#file2.txt\n#file3.txt")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "folder ** ignore rule" do
    file_list = [
      "folder1/file.txt",
      "folder1/folder2/file.txt",
      "folder1/folder3/file.txt",
      "folder1/folder2/folder3/file.txt",
      "folder1/folder2/folder3/folder4/file.txt",
      "file.txt",
      "file1.txt",
    ]

    expected_file_list = [
      "folder1/file.txt",
      "file.txt",
      "file1.txt"
    ]

    oid = create_repo_with_files(file_list, "folder1/**/file.txt")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "If a line ends in /, the whole folder should be ignored" do
    file_list = [
      "folder/file1.txt",
      "folder/file2.txt",
      "folder/file3.txt",
      "folder/folder1/file1.txt",
      "folder/folder1/file2.txt",
      "folder/folder1/file3.txt",
      "folder/folder2/file1.txt",
      "folder/folder1/folder11/file1.txt"
    ]

    expected_file_list = [
      "folder/file1.txt",
      "folder/file2.txt",
      "folder/file3.txt",
      "folder/folder2/file1.txt"
    ]

    oid = create_repo_with_files(file_list, "folder1/")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "java (gitignore) patterns" do
    file_list = [
      "folder/class1.java",
      "folder/class2.java",
      "folder/class1.class",
      "folder/class2.class",
      "folder/file3.log",
      "folder/folder1/file1.log",
      "folder/folder1/file2.log",
      "folder/folder1/file3.txt",
      "folder/folder1/file3.ctxt",
      "folder/folder2/file1.ctxt",
      "folder/folder1/folder11/file1.txt",
      "folder/temp/.mtj.tmp/a.txt",
      "folder/temp/.mtj.tmp/b.txt",
      "folder/temp/.mtj.tmp/folder/a.txt",
      "folder/x/file.java",
      "folder/x/file.jar",
      "folder/x/file.war",
      "folder/x/file.nar",
      "folder/x/file.ear",
      "folder/x/file.zip",
      "folder/x/file.tar.gz",
      "folder/x/file.rar",
      "logs/hs_err_pid_1",
      "logs/hs_err_pid_12",
      "logs/hs_err_pid_123"
    ]

    expected_file_list = [
      "folder/class1.java",
      "folder/class2.java",
      "folder/folder1/file3.txt",
      "folder/folder1/folder11/file1.txt",
      "folder/x/file.java",
    ]

    stackignore =
    "# Compiled class file\n"\
    "*.class\n"\
    "# Log file\n"\
    "*.log\n"\
    "# BlueJ files\n"\
    "*.ctxt\n"\
    "# Mobile Tools for Java (J2ME)\n"\
    ".mtj.tmp/\n"\
    "# Package Files #\n"\
    "*.jar\n"\
    "*.war\n"\
    "*.nar\n"\
    "*.ear\n"\
    "*.zip\n"\
    "*.tar.gz\n"\
    "*.rar\n"\
    "# virtual machine crash logs, see http://www.java.com/en/download/help/error_hotspot.xml\n"\
    "hs_err_pid*\n"\

    oid = create_repo_with_files(file_list, stackignore)
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "File name pattern" do
    file_list = [
      "file.txt",
      "file.0.txt",
      "file.0.1.txt",
      "file.0.1.2.txt",
      "file.0.1.2.3.4.txt",
      "file.0.1.2.3.4.5.txt",
      "file.0.1.2.3.4.5.6.7.txt",
      "file.0.1.2.3.4.5.6.8.txt",
      "file.1.1.1.txt",
      "file.a.b.c.txt",
      "folder/abc.11.22.33.44.json",
      "folder/abc.123.245.987.12121.json",
      "folder/abc.123.245.987.12121.111.json",
      "folder2/abc.123.json"
    ]

    expected_file_list = [
      "file.txt",
      "file.0.txt",
      "file.0.1.txt",
      "file.0.1.2.3.4.txt",
      "file.0.1.2.3.4.5.txt",
      "file.0.1.2.3.4.5.6.7.txt",
      "file.0.1.2.3.4.5.6.8.txt",
      "file.a.b.c.txt",
      "folder2/abc.123.json"
    ]

    oid = create_repo_with_files(file_list,
       "file.[0-9].[0-9].[0-9].txt\n"\
       "abc.[0-9]*.[0-9]*.[0-9]*.[0-9]*.json\n"\
      )
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "anchored path ignore rule" do
    file_list = [
      "file1.txt",
      "file2.txt",
      "folder1/file1.txt",
      "folder1/file2.txt",
      "folder2/folder1/file1.txt",
      "folder2/folder1/file2.txt"
    ]

    expected_file_list = [
      "file1.txt",
      "file2.txt",
      "folder2/folder1/file1.txt",
      "folder2/folder1/file2.txt"
    ]

    oid = create_repo_with_files(file_list, "/folder1/")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "dependency directories ignore rule" do
    file_list = [
      "file1.js",
      "file2.js",
      "node_modules/mod1/mod1.js",
      "node_modules/mod2/mod2.js",
      "node_modules/mod3.js",
      "node_modules/mod4.js",
      "project1/node_modules/mod1/mod1.js",
      "project1/node_modules/mod2/mod2.js",
      "project1/node_modules/mod3.js",
      "project1/node_modules/mod4.js",
      "jspm_packages/mod1/mod1.js",
      "jspm_packages/mod2/mod2.js",
      "jspm_packages/mod3.js",
      "jspm_packages/mod4.js",
      "project1/jspm_packages/mod1/mod1.js",
      "project1/jspm_packages/mod2/mod2.js",
      "project1/jspm_packages/mod3.js",
      "project1/jspm_packages/mod4.js"
    ]

    expected_file_list = [
      "file1.js",
      "file2.js"
    ]

    oid = create_repo_with_files(file_list,
      "# Dependency directories\n"\
      "node_modules/\n"\
      "jspm_packages/\n")

    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "workflow files ignore rule" do
    file_list = [
      "file1.txt",
      "file2.txt",
      ".github/workflows/workflow1.yml",
      ".github/workflows/workflow2.yml",
      "samples/workflows/workflow1.yml",
      "samples/workflows/workflow2.yml"
    ]

    expected_file_list = [
      "file1.txt",
      "file2.txt",
      "samples/workflows/workflow1.yml",
      "samples/workflows/workflow2.yml",
    ]

    oid = create_repo_with_files(file_list, "/.github/workflows/")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "Fail when more than 100 rules in .stackignore" do
    file_list = [
      "file1.txt",
      "file2.txt",
    ]

    stackignore = "file1.txt\n"
    100.times do
      stackignore += "file1.txt\n"
    end

    oid = create_repo_with_files(file_list, stackignore)
    error = assert_raises(Errors::CloneError) do
      StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    end
    assert_equal "Could not finish repository cloning. Number of ignore rules in .stackignore more than allowed", error.message
  end

  test "Pass when 100 rules in .stackignore" do
    file_list = [
      "file1.txt",
      "file2.txt",
    ]

    expected_file_list = [
      "file2.txt"
    ]
    stackignore = "file1.txt\n"
    99.times do
      stackignore += "file1.txt\n"
    end

    oid = create_repo_with_files(file_list, stackignore)
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  test "Files paths other than README.md are case-sensitive" do
    file_list = [
      "file1.txt",
      "File1.txt",
      "FILE1.txt",
      "file1.TXT",
      "README.md",
      "readme.md",
      "readme.MD"
    ]

    expected_file_list = [
      "File1.txt",
      "FILE1.txt",
      "file1.TXT",
    ]

    oid = create_repo_with_files(file_list, "file1.txt\n")
    new_tree_sha = StackignoreHelper.new.remove_ignored_files(@target_repo, oid)
    result_file_list = @target_repo.tree_file_list(new_tree_sha, skip_directories: [])
    assert_same_elements expected_file_list, result_file_list
  end

  def create_repo_with_files(path_list, stackignore = nil)
    example_repo :empty, @target_repo
    branch_name ||= @target_repo.default_branch
    base_ref = @target_repo.heads.build(branch_name)
    base_ref.append_commit({ message: "Add files", committer: @target_repo.owner }, @target_repo.owner) do |files|
      path_list.each do |path|
        files.add(path, "Test file")
      end
      files.add(".stackignore", stackignore) unless stackignore.nil?
    end
    @target_repo.ref_to_sha(branch_name)
  end
end
