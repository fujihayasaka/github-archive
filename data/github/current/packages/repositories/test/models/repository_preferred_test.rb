# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPreferredTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)
    @dot_github_repo = create(:repository, owner: @org, name: ".github")
    @local_files_repo = create(:repository, owner: @org)
  end

  setup do
    example_repo :community_files, @dot_github_repo
    example_repo :community_files, @local_files_repo
  end

  context "#preferred_file" do
    test "returns nil when repo marked as broken" do
      @local_files_repo.access.stubs(:async_broken?).returns(Promise.new.fulfill(true))
      assert_nil @local_files_repo.preferred_code_of_conduct
    end

    test "returns something when repo is not marked as broken" do
      @local_files_repo.access.stubs(:broken?).returns(false)
      assert @local_files_repo.preferred_code_of_conduct
    end
  end

  context "#preferred_code_of_conduct" do
    test "returns local code of conduct" do
      preferred_file = @local_files_repo.preferred_code_of_conduct
      assert preferred_file
      assert_equal @local_files_repo, preferred_file.repository
    end

    test "returns org level code of conduct" do
      preferred_file = @org_repo.preferred_code_of_conduct
      assert preferred_file
      assert_equal @dot_github_repo, preferred_file.repository
    end

    test "returns user level contributing" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :community_files)

      preferred_file = repo.preferred_code_of_conduct
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_contributing" do
    test "returns local contributing" do
      preferred_file = @local_files_repo.preferred_contributing
      assert preferred_file
      assert_equal @local_files_repo, preferred_file.repository
    end

    test "returns org level contributing" do
      preferred_file = @org_repo.preferred_contributing
      assert preferred_file
      assert_equal @dot_github_repo, preferred_file.repository
    end

    test "returns user level contributing" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :community_files)

      preferred_file = repo.preferred_contributing
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_issue_template" do
    test "returns local issue_template" do
      repo = create(:repository, from_example: :community_files_with_legacy_issue_template)

      preferred_file = repo.preferred_issue_template
      assert preferred_file
      assert_equal repo, preferred_file.repository
    end

    test "returns org level issue_template" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :community_files_with_legacy_issue_template)

      preferred_file = repo.preferred_issue_template
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end

    test "returns user level issue_template" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :community_files_with_legacy_issue_template)

      preferred_file = repo.preferred_issue_template
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_pull_request_template" do
    test "returns local pull_request_template" do
      preferred_file = @local_files_repo.preferred_pull_request_template
      assert preferred_file
      assert_equal @local_files_repo, preferred_file.repository
    end

    test "returns org level pull_request_template" do
      preferred_file = @org_repo.preferred_pull_request_template
      assert preferred_file
      assert_equal @dot_github_repo, preferred_file.repository
    end

    test "returns user level pull_request_template" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :community_files)

      preferred_file = repo.preferred_pull_request_template
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_support" do
    test "returns local support file" do
      repo = create(:repository, from_example: :support_file)

      preferred_file = repo.preferred_support
      assert preferred_file
      assert_equal repo, preferred_file.repository
    end

    test "returns org level support file" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :support_file)

      preferred_file = repo.preferred_support
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end

    test "returns user level support file" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :support_file)

      preferred_file = repo.preferred_support
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_funding" do
    test "returns local funding file" do
      repo = create(:repository, from_example: :funding_links)

      preferred_file = repo.preferred_funding
      assert preferred_file
      assert_equal repo, preferred_file.repository
    end

    test "returns org level funding file" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :funding_links)

      preferred_file = repo.preferred_funding
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end

    test "returns user level funding file" do
      repo = create(:repository)
      dot_github = create(:repository, owner: repo.owner, name: ".github", from_example: :funding_links)

      preferred_file = repo.preferred_funding
      assert preferred_file
      assert_equal dot_github, preferred_file.repository
    end
  end

  context "#preferred_file" do
    test "check global is default" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :funding_links)

      assert repo.preferred_file(:funding)
    end

    test "check global is false" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :funding_links)

      refute repo.preferred_file(:funding, check_global: false)
    end
  end
end
