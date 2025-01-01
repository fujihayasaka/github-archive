# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::CreateCheckAnnotationsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)

    @valid_annotation = {
      repository_id: @repository.id,
      warning_level: "warning",
      message: "This might be a problem, because reasons.",
      raw_details: "",
      filename: "README.md",
      start_line: 19,
      end_line: 19,
      start_column: 20,
      end_column: 22,
      title: "This is a Title"
    }

    @invalid_annotation = {
      repository_id: @repository.id,
      warning_level: "warning",
      message: "This might be a problem, because reasons.",
      raw_details: "",
      filename: "README.md",
      # This is an invalid annotation because the start_line is greater than the end_line
      start_line: 25,
      end_line: 19,
      start_column: 20,
      end_column: 22,
      title: "This is a Title"
    }

    @invalid_annotation_start_end_blank = {
      repository_id: @repository.id,
      warning_level: "warning",
      message: "This might be a problem, because reasons.",
      raw_details: "",
      filename: "README.md",
      start_line: "",
      end_line: "",
      start_column: 20,
      end_column: 22,
      title: "This is a Title"
    }
  end

  fixtures do
    @user = create(:user, plan:  "pro")
    @repository = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repository.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    make_trusted_oauth_apps_owner

    @check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, head_branch: nil)
  end

  context "call" do
    test "adds check suite annotations" do
      annotations = [@valid_annotation]

      Checks::CreateCheckAnnotations.call(
        check_suite: @check_suite,
        annotations: annotations,
      )

      @check_suite.reload

      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.check_annotations_count")

      assert @check_suite.annotations.any?, "Expected a annotation to be created for the check suite."
      annotation = @check_suite.annotations.last

      assert_equal "README.md", annotation.filename
      assert_equal "README.md", annotation.path
      assert_equal "warning", annotation.warning_level
      assert annotation.warning?

      assert_match /problem/, annotation.message
      assert_equal 19, annotation.start_line
      assert_equal 19, annotation.end_line
      assert_equal 20, annotation.start_column
      assert_equal 22, annotation.end_column
      assert_equal "This is a Title", annotation.title
    end

    test "adds additional annotations to existing ones" do
      annotation = {
        filename: "README.md",
        warning_level: "warning",
        start_line: 122,
        end_line: 123,
        repository_id: @repository.id
      }
      CheckAnnotation.create!(annotation.merge(message: "one", check_suite: @check_suite))

      annotation_attrs = {
        repository_id: @repository.id,
        warning_level: "warning",
        message: "two",
        raw_details: "",
        filename: "README.md",
        start_line: 19,
        end_line: 19,
        start_column: 20,
        end_column: 22,
        title: "This is a Title"
      }
      annotations = [annotation_attrs.merge(message: "two")]

      Checks::CreateCheckAnnotations.call(
        check_suite: @check_suite,
        annotations: annotations,
      )

      @check_suite.reload

      # Assertions on the created output data on the check_run
      assert_equal 2, @check_suite.annotations.count
      annotation = @check_suite.annotations.last

      assert_equal "README.md", annotation.filename
      assert_equal "README.md", annotation.path
      assert_equal "warning", annotation.warning_level
      assert_match(/two/, annotation.message)
    end

    test "does not add nil annotations to existing ones" do
      annotation = {
        filename: "README.md",
        warning_level: "warning",
        start_line: 122,
        end_line: 123,
        message: "one",
        repository: @check_suite.repository
      }
      @check_suite.annotations.create!(annotation)

      annotations = nil

      Checks::CreateCheckAnnotations.call(
        check_suite: @check_suite,
        annotations: annotations,
      )

      @check_suite.reload

      # Assertions on the created output data on the check_run
      assert_equal 1, @check_suite.annotations.count
    end

    test "failing annotation validations do not raise errors" do
      annotations = [@invalid_annotation]

      assert_nothing_raised do
        Checks::CreateCheckAnnotations.call(
          check_suite: @check_suite,
          annotations: annotations,
        )
      end

      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.invalid_annotations_count")
    end

    test "saves valid annotations even when invalid ones are present" do
      annotations = [@valid_annotation, @invalid_annotation]

      Checks::CreateCheckAnnotations.call(
        check_suite: @check_suite,
        annotations: annotations,
      )

      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.check_annotations_count")
      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.invalid_annotations_count")
    end

    test "saves truncated annotations list when exceeding max per request" do
      annotations = Array.new(26) { @valid_annotation }

      Checks::CreateCheckAnnotations.call(
        check_suite: @check_suite,
        annotations: annotations,
      )

      assert_dogstats_count_value(25, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.check_annotations_count")
    end
  end

  context "remove_invalid_annotations" do
    test "removes invalid annotations" do
      invalid_annotations = [@invalid_annotation]

      expected_log = {
        "Body" => "encountered invalid annotations",
        "gh.repository.id" => @repository.id,
        "invalid_check_annotations.count" => invalid_annotations.count,
        "annotation_errors" => [{ errors:
          {
            start_line: ["must be less than or equal to `end_line`"],
            end_line: ["must be greater than or equal to `start_line`"],
            start_column: ["can't be provided across multiple lines"],
            end_column: ["can't be provided across multiple lines"]
          }
        }]
      }

      assert_logged(**expected_log) do
        filtered_annotations = Checks::CreateCheckAnnotations.remove_invalid_annotations(
          invalid_annotations,
          @repository.id,
          Checks::CreateCheckAnnotations::STATS_PREFIX,
          "class_name",
          "function_name",
        )

        assert_equal 0, filtered_annotations.count
      end

      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.invalid_annotations_count")
    end

    test "does not remove valid annotations" do
      annotations = [@valid_annotation, @invalid_annotation]

      filtered_annotations = Checks::CreateCheckAnnotations.remove_invalid_annotations(
        annotations,
        @repository.id,
        Checks::CreateCheckAnnotations::STATS_PREFIX,
        "class_name",
        "function_name",
      )

      assert_dogstats_count_value(1, "#{Checks::CreateCheckAnnotations::STATS_PREFIX}.invalid_annotations_count")

      assert_equal 1, filtered_annotations.count
    end

    test "overrides blank start/end line with 0" do
      annotations = [@invalid_annotation_start_end_blank]

      filtered_annotations = Checks::CreateCheckAnnotations.remove_invalid_annotations(
        annotations,
        @repository.id,
        Checks::CreateCheckAnnotations::STATS_PREFIX,
        "class_name",
        "function_name",
      )

      assert_equal 1, filtered_annotations.count

      annotation = filtered_annotations.first

      assert_equal 0, annotation[:start_line]
      assert_equal 0, annotation[:end_line]
    end
  end
end
