# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckAnnotationTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  context "validation" do
    test "requires a path" do
      annotation = CheckAnnotation.new
      annotation.valid?

      refute annotation.errors[:path].blank?
    end

    test "requires a start_line" do
      annotation = CheckAnnotation.new
      annotation.valid?

      refute annotation.errors[:start_line].blank?
    end

    test "requires an end_line" do
      annotation = CheckAnnotation.new
      annotation.valid?

      refute annotation.errors[:end_line].blank?
    end

    test "requires line numbers to not mismatch" do
      attrs = {
        path: "README.md",
        start_line: 125,
        end_line: 120,
        title: "My Title",
      }
      annotation = CheckAnnotation.create(attrs)
      refute annotation.valid?

      assert_equal ["must be less than or equal to `end_line`"], annotation.errors[:start_line]
      assert_equal ["must be greater than or equal to `start_line`"], annotation.errors[:end_line]
    end

    test "requires a annotation_level" do
      annotation = CheckAnnotation.new
      annotation.valid?

      refute annotation.errors[:annotation_level].blank?
    end

    test "requires a message" do
      annotation = CheckAnnotation.new
      annotation.valid?

      refute annotation.errors[:message].blank?
    end

    test "supports emoji in title" do
      attrs = {
        path: "README.md",
        start_line: 123,
        end_line: 124,
        title: "My Title 👍🏽",
      }

      annotation = CheckAnnotation.new(attrs)
      annotation.valid?

      assert annotation.errors[:title].blank?
      assert_equal "My Title 👍🏽", annotation.title
    end

    test "supports emoji in message" do
      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "This might be a problem 🙀",
        start_line: 123,
        end_line: 123,
        start_column: 1,
        end_column: 10,
        title: "My Title",
      }

      annotation = CheckAnnotation.new(attrs)
      annotation.valid?

      assert annotation.errors[:message].blank?
      assert_equal "This might be a problem 🙀", annotation.message
    end
  end
  context "#title" do
    test "uses title if present" do
      attrs = {
        path: "README.md",
        start_line: 123,
        end_line: 124,
        title: "My Title",
      }

      annotation = CheckAnnotation.new(attrs)
      annotation.valid?

      assert annotation.errors[:title].blank?
      assert_equal "My Title", annotation.title
    end

    test "uses default if no title is present" do
      attrs = {
        path: "README.md",
        start_line: 123,
        end_line: 124,
      }

      annotation = CheckAnnotation.new(attrs)

      assert_equal "README.md#L123-L124", annotation.title
    end

    test "default doesn't duplicate line numbers" do
      attrs = {
        path: "README.md",
        start_line: 123,
        end_line: 123,
      }

      annotation = CheckAnnotation.new(attrs)

      assert_equal "README.md#L123", annotation.title
    end

    test "returns a UTF-8 string" do
      attrs = {
        path: "README.md",
        start_line: 123,
        end_line: 123,
        title: "other encoding".dup.tap { |t| t.force_encoding("ISO-8859-1") },
      }

      annotation = CheckAnnotation.new(attrs)

      assert_equal Encoding::UTF_8, annotation.title.encoding
    end
  end
  context "#parent_type" do
    test "returns workflow run if workflow run and check suite present" do
      make_trusted_oauth_apps_owner
      @repository = create :repository
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository

      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_suite.repository_id,
        check_suite: check_suite
      }

      annotation = CheckAnnotation.create!(attrs)

      expected = "workflow run"
      expected = "check suite" if !GitHub.actions_enabled?

      assert_equal expected, annotation.parent_type
    end

    test "returns check suite if check suite present and no workflow run" do
      check_suite = create :check_suite

      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_suite.repository_id,
        check_suite: check_suite
      }

      annotation = CheckAnnotation.create!(attrs)

      assert_equal "check suite", annotation.parent_type
    end

    test "returns workflow job if workflow job run for actions" do
      make_trusted_oauth_apps_owner
      @repository = create :repository
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      check_run = create :check_run, check_suite: check_suite, repository: check_suite.repository
      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_run.repository.id,
        check_run: check_run
      }

      annotation = CheckAnnotation.create!(attrs)

      expected = "workflow job"
      expected = "check run" if !GitHub.actions_enabled?

      assert_equal expected, annotation.parent_type
    end

    test "returns check run if check run for not actions" do
      check_suite = create :check_suite
      check_run = create :check_run, check_suite: check_suite, repository: check_suite.repository
      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_run.repository.id,
        check_run: check_run
      }

      annotation = CheckAnnotation.create!(attrs)

      assert_equal "check run", annotation.parent_type
    end
  end
  context "#column" do
    test "accepts column information" do
      repository = create(:repository)

      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 123,
        end_line: 123,
        start_column: 1,
        end_column: 10,
        title: "My Title",
        repository: repository,
      }

      annotation = CheckAnnotation.new(attrs)
      assert annotation.valid?

      assert_equal 1, annotation.start_column
      assert_equal 10, annotation.end_column
    end
    test "does not accept column information across multiple lines" do
      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 123,
        end_line: 125,
        start_column: 1,
        end_column: 10,
        title: "My Title",
      }

      annotation = CheckAnnotation.create(attrs)
      refute annotation.valid?

      assert_equal ["can't be provided across multiple lines"], annotation.errors[:start_column]
      assert_equal ["can't be provided across multiple lines"], annotation.errors[:end_column]
    end
    test "does not accept column information that's mismatched" do
      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 123,
        end_line: 123,
        start_column: 10,
        end_column: 1,
        title: "My Title",
      }

      annotation = CheckAnnotation.create(attrs)
      refute annotation.valid?

      assert_equal ["must be less than or equal to `end_column`"], annotation.errors[:start_column]
      assert_equal ["must be greater than or equal to `start_column`"], annotation.errors[:end_column]
    end

    test "accepts column information if only start_column is set" do
      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "Annotation with only a start_column",
        start_line: 123,
        end_line: 123,
        start_column: 10,
        title: "My Title",
      }

      annotation = CheckAnnotation.new(attrs)
      assert annotation.valid?

      assert_equal 10, annotation.start_column
      assert_nil annotation.end_column
    end

    test "accepts column information if only end_column is set" do
      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "Annotation with only a end_column",
        start_line: 123,
        end_line: 123,
        end_column: 5,
        title: "My Title",
      }

      annotation = CheckAnnotation.new(attrs)
      assert annotation.valid?

      assert_nil annotation.start_column
      assert_equal 5, annotation.end_column
    end
  end

  context "it clears the check annotation" do
    test "after check suite destruction" do
      check_suite = create :check_suite
      check_run   = create :check_run, check_suite: check_suite, repository: check_suite.repository

      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_run.repository_id,
      }

      annotation = CheckAnnotation.create!(attrs.merge(message: "hey", check_run: check_run))

      assert_difference('CheckAnnotation.annotate("cross-shard-query-exempted").count', -1) do
        only = [DestroyDependentRecordsJob]
        perform_enqueued_jobs(only: only) do
          check_suite.destroy
        end
      end
    end

    test "after check run destruction" do
      check_suite = create :check_suite
      check_run   = create :check_run, check_suite: check_suite, repository: check_suite.repository

      attrs = {
        path: "README.md",
        annotation_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository: check_run.repository,
      }

      annotation = CheckAnnotation.create!(attrs.merge(message: "hey", check_run: check_run))

      assert_difference('CheckAnnotation.annotate("cross-shard-query-exempted").count', -1) do
        only = [DestroyDependentRecordsJob]
        perform_enqueued_jobs(only: only) do
          check_run.destroy
        end
      end
    end

    test "after repo destruction" do
      check_suite = create :check_suite
      check_run   = create :check_run, check_suite: check_suite

      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository: check_run.repository,
      }

      annotation = CheckAnnotation.create!(attrs.merge(message: "hey", check_run: check_run))

      repo = check_suite.repository
      repo.remove(repo.owner, synchronous: true)

      assert_difference('CheckAnnotation.annotate("cross-shard-query-exempted").count', -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          repo.purge(synchronous: true)
        end
      end
    end
  end

  context "#truncate_fields" do
    test "truncates varbinary fields" do
      too_long_vb = "a" * 2000 # too long for max varbinary columns
      too_long_bt = "a" * 66666 # too long for max blob or text columns
      annotation = create :check_annotation, filename: too_long_vb, title: too_long_vb, raw_details: too_long_bt, message: too_long_bt

      assert_equal CheckAnnotation::MAX_VARBINARY_FIELD_LENGTH, annotation.filename.bytesize
      assert_equal CheckAnnotation::MAX_VARBINARY_FIELD_LENGTH, annotation.title.bytesize
      assert_equal CheckAnnotation::MAX_BLOB_OR_TEXT_FIELD_LENGTH, annotation.raw_details.bytesize
      assert_equal CheckAnnotation::MAX_BLOB_OR_TEXT_FIELD_LENGTH, annotation.message.bytesize
    end

    test "reports truncation stats to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create :check_annotation, title: title = "a" * 2000

      assert_equal 1, GitHub.dogstats.increments("field_truncator", tags: ["class:CheckAnnotation", "field:title"]).length
    end
  end

  [:filename].each do |field|
    test "supports emoji for #{field}" do
      annotation = create(:check_annotation, field => "we ❤️ emojis")
      assert_multibyte_tracked_changes(annotation, field)
    end
  end

  context "parsed_file_name" do
    test "returns expected file for a non actions check suite annotation" do
      check_suite = create :check_suite
      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_suite.repository.id,
        check_suite: check_suite
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal "README.md", annotation.parsed_file_name
    end

    test "returns expected file for a non actions check run annotation" do
      check_suite = create :check_suite
      check_run = create :check_run, check_suite: check_suite, repository: check_suite.repository
      attrs = {
        filename: "README.md",
        warning_level: "warning",
        message: "This might be a problem, because reasons.",
        start_line: 122,
        end_line: 123,
        raw_details: "This is just text.",
        repository_id: check_run.repository.id,
        check_run: check_run
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal "README.md", annotation.parsed_file_name
    end

    test "returns expected file for a normal workflow's actions check suite annotation" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app
      attrs = {
        filename: ".github/workflows/ci.yml",
        warning_level: "failure",
        message: "This might be a problem, because reasons.",
        start_line: 10,
        end_line: 12,
        raw_details: "This is just text.",
        repository_id: check_suite.repository.id,
        check_suite: check_suite
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal ".github/workflows/ci.yml", annotation.parsed_file_name
    end

    test "returns expected file for a normal workflow's actions check run annotation" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app
      check_run = create :check_run, repository: check_suite.repository, check_suite: check_suite
      attrs = {
        filename: ".github/workflows/ci.yml",
        warning_level: "failure",
        message: "This might be a problem, because reasons.",
        start_line: 10,
        end_line: 12,
        raw_details: "This is just text.",
        repository_id: check_suite.repository.id,
        check_run: check_run
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal ".github/workflows/ci.yml", annotation.parsed_file_name
    end

    test "returns expected file for a required workflow's actions check suite annotation" do
      make_trusted_oauth_apps_owner
      source_repo = create :repository
      req_workflow_path = "required/#{source_repo.id}/required/ci.yml"

      check_suite = create :check_suite_for_actions_app, workflow_file_path: req_workflow_path
      attrs = {
        filename: "required/#{source_repo.id}/required/ci.yml",
        warning_level: "failure",
        message: "This might be a problem, because reasons.",
        start_line: 10,
        end_line: 12,
        raw_details: "This is just text.",
        repository_id: check_suite.repository.id,
        check_suite: check_suite
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal "#{source_repo.nwo}/required/ci.yml", annotation.parsed_file_name
    end

    test "returns expected file for a required workflow's actions check run annotation" do
      make_trusted_oauth_apps_owner
      source_repo = create :repository
      req_workflow_path = "required/#{source_repo.id}/required/ci.yml"

      check_suite = create :check_suite_for_actions_app, workflow_file_path: req_workflow_path
      check_run = create :check_run, check_suite: check_suite
      attrs = {
        filename: "required/#{source_repo.id}/required/ci.yml",
        warning_level: "failure",
        message: "This might be a problem, because reasons.",
        start_line: 10,
        end_line: 12,
        raw_details: "This is just text.",
        repository_id: check_suite.repository.id,
        check_run: check_run
      }

      annotation = CheckAnnotation.create!(attrs)
      assert_equal "#{source_repo.nwo}/required/ci.yml", annotation.parsed_file_name
    end
  end

  context "field compression" do
    [:message].each do |field|
      test "compresses #{field} field" do
        dummy_field = "a" * 2000
        check_annotation = build :check_annotation
        check_annotation[field] = dummy_field
        check_annotation.save!

        raw = check_annotation.read_attribute_before_type_cast(field)

        assert_equal check_annotation[field], dummy_field
        refute_equal raw.to_s, dummy_field
        assert Checks::MaybeCompressed.is_compressed?(raw.to_s)
      end
    end
  end

  context "#system_path?" do
    test "is true when the path is set by the system" do
      annotation = create(:check_annotation, filename: CheckAnnotation::ACTIONS_SYSTEM_PATH)
      assert annotation.system_path?
    end

    test "is false when the path is not the system path" do
      annotation = create(:check_annotation, filename: "not/system/path")
      refute annotation.system_path?
    end
  end
end
