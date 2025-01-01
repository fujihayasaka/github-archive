# typed: true
# frozen_string_literal: true

require "test_helper"

class Issue::IssueTypeDependencyTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:issue_types)

    @owner = create(:user)
    @read_user = create(:user)
    @org = create(:organization, admin: @owner)
    @org.add_member(@read_user, action: :read)
    @issue_type = @org.issue_types.first

    @repo = create(:repository, owner: @org)
    @existing_issue = create(:issue, repository: @repo)
  end

  context "create - validation" do
    test "cannot create an issue with an issue type if the FF is disabled" do
      disable_feature_flag(:issue_types)

      issue = Issue.new(repository: @repo, issue_type: @issue_type, title: "test", user: @owner)
      refute issue.valid?
      assert issue.errors.of_kind?(:base, :issue_type_is_not_a_valid_attribute),
        "Expected issue to not allow issue type if the FF is disabled"
    end

    test "cannot set the issue type if the issue type belongs to a different owner" do
      different_org = create(:organization)
      issue = Issue.new(repository: @repo, issue_type: different_org.issue_types.first, title: "test", user: @owner)
      refute issue.valid?
      assert issue.errors.of_kind?(:issue_type_id, :not_found),
        "Expected issue to not allow issue type if the issue type is not found"
    end

    test "cannot set the issue type if the issue type is disabled" do
      @issue_type.update!(enabled: false)
      issue = Issue.new(repository: @repo, issue_type: @issue_type, title: "test", user: @owner)
      refute issue.valid?
      assert issue.errors.of_kind?(:issue_type_id, :not_enabled),
        "Expected issue to not allow issue type if the issue type is disabled"
    end

    test "cannot set a private issue type on an issue in a public repository", skip_with_all_emus: true do
      repository = create(:public_repository, owner: @org)
      issue = Issue.new(repository: repository, issue_type: create(:issue_type, owner: @org, private: true, enabled: true), title: "test", user: @owner)
      refute issue.valid?
      assert issue.errors.of_kind?(:issue_type_id, :cannot_be_used_in_public_repositories),
        "Expected issue to not allow issue type if the issue type is private and the repo is public"
    end

    test "successfully creates the issue with an issue type" do
      issue = Issue.create!(repository: @repo, issue_type: @issue_type, title: "test", user: @owner)
      assert issue.valid?
    end
  end

  context "update - validation" do
    test "cannot create an issue with an issue type if the FF is disabled" do
      disable_feature_flag(:issue_types)

      @existing_issue.update(issue_type: @issue_type)
      refute @existing_issue.valid?
      assert @existing_issue.errors.of_kind?(:base, :issue_type_is_not_a_valid_attribute),
        "Expected issue to not allow issue type if the FF is disabled"
    end

    test "cannot set the issue type if the issue type belongs to a different owner" do
      different_org = create(:organization)
      @existing_issue.update(issue_type: different_org.issue_types.first)
      refute @existing_issue.valid?
      assert @existing_issue.errors.of_kind?(:issue_type_id, :not_found),
        "Expected issue to not allow issue type if the issue type is not found"
    end

    test "cannot set the issue type if the issue type is disabled" do
      @issue_type.update!(enabled: false)
      @existing_issue.update(issue_type: @issue_type)
      refute @existing_issue.valid?
      assert @existing_issue.errors.of_kind?(:issue_type_id, :not_enabled),
        "Expected issue to not allow issue type if the issue type is disabled"
    end

    test "cannot set a private issue type on an issue in a public repository", skip_with_all_emus: true do
      repository = create(:public_repository, owner: @org)
      issue = create(:issue, repository: repository)
      issue.update(issue_type: create(:issue_type, owner: @org, private: true, enabled: true))
      refute issue.valid?
      assert issue.errors.of_kind?(:issue_type_id, :cannot_be_used_in_public_repositories),
        "Expected issue to not allow issue type if the issue type is private and the repo is public"
    end

    test "successfully creates the issue with an issue type" do
      @existing_issue.update!(issue_type: @issue_type)
      assert @existing_issue.valid?
    end

    test "successfully updates the issue to not have an issue type" do
      issue = create(:issue, issue_type: @issue_type, repository: @repo, user: @owner)
      issue.update(issue_type: nil)
      assert issue.valid?
    end

    test "can update other issue fields regardless of if the issue type is disabled" do
      @existing_issue.update(issue_type: @issue_type)
      @issue_type.update!(enabled: false)

      @existing_issue.update(title: "ta da!")
      assert @existing_issue.valid?
    end

    test "can update issue with previously added issue type when FF is disabled" do
      @existing_issue.update(issue_type: @issue_type)

      disable_feature_flag(:issue_types)

      @existing_issue.update(body: "update issue body!")
      assert @existing_issue.valid?
    end

    test "cannot change issue type when FF is disabled" do
      new_issue_type = @org.issue_types.last
      @existing_issue.update(issue_type: @issue_type)
      @existing_issue.reload

      disable_feature_flag(:issue_types)

      @existing_issue.update(issue_type: new_issue_type)

      refute @existing_issue.valid?
    end
  end
end
