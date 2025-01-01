# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module Annotations
      class PayloadTest < GitHub::TestCase
        fixtures do
          @admin = create(:user, login: "wiseguy")
          @user_session = create(:authentication_record, user: @admin).user_session
          @org = create :organization, plan: "bronze", admin: @admin
          @repo = create(:private_repository, owner: @admin, from_example: :review_comment_fork)

          @pull = create(:pull_request,
            repository:      @repo,
            base_repository: @repo,
            base_user:       @repo.owner,
            base_ref:        "master",
            head_repository: @repo,
            head_user:       @repo.owner,
            head_ref:        "topic",
            user:            @repo.owner
          )

          @default_check_suite = create(
            :check_suite,
            repository: @pull.repository,
            head_sha: @pull.head_sha,
            head_branch: @pull.head_ref,
            name: "coverage"
          )

          @notice_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :success)
          @warning_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)
          @failure_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)

          @notice_annotation = create(
            :check_annotation,
            check_run: @notice_annotation_check_run,
            path: "app/packages/ui/types.ts",
            annotation_level: "notice",
            start_line: 5,
            end_line: 7
          )
          @warning_annotation = create(
            :check_annotation,
            check_run: @warning_annotation_check_run,
            path: "app/packages/ui/tabs.spec.ts",
            annotation_level: "warning",
            start_line: 4,
            end_line: 6
          )
          @failure_annotation = create(
            :check_annotation,
            check_run: @failure_annotation_check_run,
            path: "app/packages/ui/spaces.spec.ts",
            annotation_level: "failure",
            start_line: 3,
            end_line: 5
          )
        end

        context "#call" do
          test "builds and return T::Array[Annotation] objects" do
            loader_data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            payload = loader_data = PullRequests::PageData::Annotations::Payload.call(loader_data)

            # Sort by annotationLevel to avoid flaky gauntlet test issues due to ordering expectations in the assert_equal
            payload.sort_by! { |a| a.annotationLevel }

            expected_payload = [
              {
                annotationLevel: "FAILURE",
                appAvatarAltText: "#{@default_check_suite.github_app.name} avatar image",
                appAvatarUrl: @default_check_suite.github_app.preferred_avatar_url(size: 20),
                checkRun: {
                  detailsUrl: @failure_annotation_check_run.details_url,
                  name: @failure_annotation_check_run.name
                },
                checkSuiteName: @failure_annotation_check_run.check_suite.name,
                databaseId: @failure_annotation.id,
                endLine: @failure_annotation.end_line,
                id: @failure_annotation.global_relay_id,
                message: @failure_annotation.message.dup.force_encoding("UTF-8"),
                path: @failure_annotation.path.dup.force_encoding("UTF-8"),
                pathDigest: Digest::SHA256.hexdigest(@failure_annotation.path),
                startLine: @failure_annotation.start_line,
                title: @failure_annotation.title.dup.force_encoding("UTF-8"),
              },
              {
                annotationLevel: "NOTICE",
                appAvatarAltText: "#{@default_check_suite.github_app.name} avatar image",
                appAvatarUrl: @default_check_suite.github_app.preferred_avatar_url(size: 20),
                checkRun: {
                  detailsUrl: @notice_annotation_check_run.details_url,
                  name: @notice_annotation_check_run.name
                },
                checkSuiteName: @notice_annotation_check_run.check_suite.name,
                databaseId: @notice_annotation.id,
                endLine: @notice_annotation.end_line,
                id: @notice_annotation.global_relay_id,
                message: @notice_annotation.message.dup.force_encoding("UTF-8"),
                path: @notice_annotation.path.dup.force_encoding("UTF-8"),
                pathDigest: Digest::SHA256.hexdigest(@notice_annotation.path),
                startLine: @notice_annotation.start_line,
                title: @notice_annotation.title.dup.force_encoding("UTF-8"),
              },
              {
                annotationLevel: "WARNING",
                appAvatarAltText: "#{@default_check_suite.github_app.name} avatar image",
                appAvatarUrl: @default_check_suite.github_app.preferred_avatar_url(size: 20),
                checkRun: {
                  detailsUrl: @warning_annotation_check_run.details_url,
                  name: @warning_annotation_check_run.name
                },
                checkSuiteName: @warning_annotation_check_run.check_suite.name,
                databaseId: @warning_annotation.id,
                endLine: @warning_annotation.end_line,
                id: @warning_annotation.global_relay_id,
                message: @warning_annotation.message.dup.force_encoding("UTF-8"),
                path: @warning_annotation.path.dup.force_encoding("UTF-8"),
                pathDigest: Digest::SHA256.hexdigest(@warning_annotation.path),
                startLine: @warning_annotation.start_line,
                title: @warning_annotation.title.dup.force_encoding("UTF-8"),
              },
            ]

            assert_equal expected_payload.as_json, payload.as_json
          end

          test "does not make a database call" do
            loader_data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            assert_no_queries do
              PullRequests::PageData::Annotations::Payload.call(loader_data)
            end
          end
        end

        context "#annotations_highest_level" do
          test "returns a hash of the highest annotation level for each path" do
            loader_data = PullRequests::PageData::Annotations::Loader.load_annotation_levels_with_path(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            annotations = PullRequests::PageData::Annotations::Payload.annotations_highest_level(loader_data)

            expected_annotations = {
              "app/packages/ui/types.ts" => "NOTICE",
              "app/packages/ui/tabs.spec.ts" => "WARNING",
              "app/packages/ui/spaces.spec.ts" => "FAILURE"
            }

            assert_equal expected_annotations, annotations
          end
        end
      end
    end
  end
end
