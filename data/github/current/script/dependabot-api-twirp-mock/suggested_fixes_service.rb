# frozen_string_literal: true

require "proto-dependabot-api"

module SuggestedFixesService
  def get_suggested_fix(req, res)
    request_proto = decode_protobuf_request(req, DependabotApi::V1::GetSuggestedFixRequest)
    return json_response(res, { error: "Invalid Protobuf format" }, 400) if request_proto.nil?

    # Extract parameters from the request
    autofix_job_id = request_proto.autofix_job_id
    github_pull_request_number = request_proto.github_pull_request_number
    github_repo_id = request_proto.github_repo_id

    if autofix_job_id.nil? || github_pull_request_number.nil? || github_repo_id.nil?
      log_to_console("Missing required parameters")
      return json_response(res, { error: "Missing required parameters: autofix_job_id, github_pull_request_number, github_repo_id" }, 422)
    end

    # Log the incoming parameters
    log_to_console("Params: autofix_job_id=#{autofix_job_id}, github_pull_request_number=#{github_pull_request_number}, github_repo_id=#{github_repo_id}")

    # Create the Protobuf response
    proto_response(res,
      DependabotApi::V1::GetSuggestedFixResponse.new(
        suggested_fix: DependabotApi::V1::SuggestedFix.new(
          id: 1,
          autofix_job_id: 123456,
          description: "The breaking change detected by Dependabot is due to the use of the _.pluck method from the lodash library, which was removed in version 4.17.21. To fix this issue, we need to replace the _.pluck method with an equivalent method that is still supported in the latest version of lodash. The _.map method can be used as a replacement for _.pluck.",
          files: [
            DependabotApi::V1::SuggestedFixFile.new(
              file_path: "lodash-example/src/main-test.js",
              diff_content: "diff --git a/lodash-example/src/main-test.js b/lodash-example/src/main-test.js\n--- a/lodash-example/src/main-test.js\n+++ b/lodash-example/src/main-test.js\n@@ -1,7 +1,7 @@\n const _ = require('lodash');\n \n function getNames(users) {\n-  return _.pluck(users, 'user');\n+  return _.map(users, 'user');\n }\n \n // Test function\n",
              created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
              updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec)
            )
          ],
          review_status: DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_UNREVIEWED,
          created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
          updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
          dependency_metadata: []
        )
      )
    )
  end

  def apply_suggested_fix(req, res)
    request_proto = decode_protobuf_request(req, DependabotApi::V1::ApplySuggestedFixRequest)
    return json_response(res, { error: "Invalid Protobuf format" }, 400) if request_proto.nil?

    autofix_job_id = request_proto.autofix_job_id
    github_pull_request_number = request_proto.github_pull_request_number
    github_repo_id = request_proto.github_repo_id

    if autofix_job_id.nil? || github_pull_request_number.nil? || github_repo_id.nil?
      log_to_console("Missing required parameters")
      return json_response(res, { error: "Missing required parameters: autofix_job_id, github_pull_request_number, github_repo_id" }, 422)
    end

    # Log the incoming parameters
    log_to_console("Params: autofix_job_id=#{autofix_job_id}, github_pull_request_number=#{github_pull_request_number}, github_repo_id=#{github_repo_id}")

    # Create the Protobuf response
    proto_response(res, DependabotApi::V1::ApplySuggestedFixResponse.new(success: true))
  end

  def mock_suggested_fixes_service(server)
    server.mount_proc "/twirp/DependabotApi.v1.SuggestedFixes/GetSuggestedFix", &method(:get_suggested_fix)
    server.mount_proc "/twirp/DependabotApi.v1.SuggestedFixes/ApplySuggestedFix", &method(:apply_suggested_fix)
  end
end
