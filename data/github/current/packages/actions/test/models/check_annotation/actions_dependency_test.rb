# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckAnnotationActionsDependencyTest < GitHub::TestCase
  context "#parse_and_format_required_workflow_filename" do
    test "returns formatted workflow file path for required workflow check suite annotation" do
      make_trusted_oauth_apps_owner

      org = create :organization
      source_repo = create :repository, owner: org
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

      assert_equal "#{source_repo.nwo}/required/ci.yml", annotation.parse_and_format_required_workflow_filename
    end
  end
end
