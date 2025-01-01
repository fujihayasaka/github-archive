# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuitesDomainTest < GitHub::TestCase
  fixtures do
    @repository = create :repository, from_example: :simple
    @github_app = create :integration

    @after = @repository.heads.find("master").target_oid

    make_integration_installation integration: @github_app, repository: @repository
  end

  context "#find_or_create_check_suite" do
    context "when a check suite already exists" do
      test "returns the check suite with matching head_sha and github_app_id" do
        existing_check_suite = create(
          :check_suite,
          github_app: @github_app,
          head_sha: @after,
          repository: @repository,
        )

        assert_no_difference "CheckSuite.where(repository_id: #{@repository.id}).count" do
          check_suite = Checks.domain.check_suites.find_or_create(
            repo: @repository,
            head_sha: @after,
            github_app_id: @github_app.id,
          )

          assert_equal existing_check_suite.id, check_suite.id
        end
      end

      test "returns the check suite with matching github_app_id and push" do
        CheckSuite.any_instance.stubs(:present?).returns(false).once

        push = create :push, after: @after, repository: @repository
        existing_check_suite = create(
          :check_suite,
          github_app_id: @github_app.id,
          head_sha: @after,
          repository_id: @repository.id,
          head_branch: push.branch_name,
          push_id: push.id,
        )

        assert_no_difference "CheckSuite.where(repository_id: #{@repository.id}).count" do
          check_suite = Checks.domain.check_suites.find_or_create(
            repo: @repository,
            head_sha: @after,
            github_app_id: @github_app.id,
          )

          assert_equal existing_check_suite.id, check_suite.id
        end
      end
    end

    context "when a check suite doesn't yet exist" do
      test "creates a new check suite" do
        assert_difference "CheckSuite.where(repository_id: #{@repository.id}).count" do
          check_suite = Checks.domain.check_suites.find_or_create(
            repo: @repository,
            head_sha: @after,
            github_app_id: @github_app.id,
          )

          refute_nil check_suite
        end
      end
    end

    context "when a RecordNotUnique is raised" do
      test "after retrying three times returns the existing check suite" do
        push = create :push, after: @after, repository: @repository
        existing_check_suite = create(
          :check_suite,
          github_app_id: @github_app.id,
          head_sha: @after,
          repository_id: @repository.id,
          head_branch: push.branch_name,
          push_id: push.id,
        )
        check_suites = @repository.check_suites

        check_suites_mock = mock
        check_suites_mock.stubs(:find_by).returns(nil)
        check_suites_mock
          .stubs(:create!)
          .raises(ActiveRecord::RecordNotUnique.new("Not Unique Stub"))

        # Stub first 3 attempts then return check_suites
        @repository
          .stubs(:check_suites)
          .returns(
            check_suites_mock,                    # Pass the early find_by check
            check_suites_mock, check_suites_mock, # Attempt #1
            check_suites_mock, check_suites_mock, # Attempt #2
            check_suites_mock, check_suites_mock  # Attempt #3
          )
          .then
          .returns(check_suites)

        assert_no_difference "CheckSuite.where(repository_id: #{@repository.id}).count" do
          check_suite = Checks.domain.check_suites.find_or_create(
            repo: @repository,
            head_sha: @after,
            github_app_id: @github_app.id,
          )

          assert_equal existing_check_suite.id, check_suite.id
        end
      end

      test "raises a RecordNotUnique after retrying three times" do
        check_suites_mock = mock
        check_suites_mock.stubs(:find_by).returns(nil)
        check_suites_mock
          .stubs(:create!)
          .raises(ActiveRecord::RecordNotUnique.new("Not Unique Stub"))

        @repository.stubs(:check_suites).returns(check_suites_mock)

        exception = assert_raises ActiveRecord::RecordNotUnique do
          check_suite = Checks.domain.check_suites.find_or_create(
            repo: @repository,
            head_sha: @after,
            github_app_id: @github_app.id,
          )
        end
      end
    end
  end
end
