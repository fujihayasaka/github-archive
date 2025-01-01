# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module Annotations
      class LoaderTest < GitHub::TestCase
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
        end

        test "returns expected data" do
          notice_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :success)
          warning_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)
          failure_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)

          notice_annotation = create(
            :check_annotation,
            check_run: notice_annotation_check_run,
            path: "app/packages/ui/types.ts",
            annotation_level: "notice",
            start_line: 5,
            end_line: 7
          )
          warning_annotation = create(
            :check_annotation,
            check_run: warning_annotation_check_run,
            path: "app/packages/ui/tabs.spec.ts",
            annotation_level: "warning",
            start_line: 4,
            end_line: 6
          )
          failure_annotation = create(
            :check_annotation,
            check_run: failure_annotation_check_run,
            path: "app/packages/ui/spaces.spec.ts",
            annotation_level: "failure",
            start_line: 3,
            end_line: 5
          )

          data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
          assert_equal 3, data.size

          loader_notice_annotation = T.must(data.find { |e| e.annotation_level == "notice" })
          loader_warning_annotation = T.must(data.find { |e| e.annotation_level == "warning" })
          loader_failure_annotation = T.must(data.find { |e| e.annotation_level == "failure" })

          assert_equal "app/packages/ui/types.ts", loader_notice_annotation.path
          assert_equal "app/packages/ui/tabs.spec.ts", loader_warning_annotation.path
          assert_equal "app/packages/ui/spaces.spec.ts", loader_failure_annotation.path

          assert_equal "notice", loader_notice_annotation.annotation_level
          assert_equal "warning", loader_warning_annotation.annotation_level
          assert_equal "failure", loader_failure_annotation.annotation_level

          assert_equal notice_annotation.start_line, loader_notice_annotation.start_line
          assert_equal warning_annotation.start_line, loader_warning_annotation.start_line
          assert_equal failure_annotation.start_line, loader_failure_annotation.start_line

          assert_equal notice_annotation.end_line, loader_notice_annotation.end_line
          assert_equal warning_annotation.end_line, loader_warning_annotation.end_line
          assert_equal failure_annotation.end_line, loader_failure_annotation.end_line

          assert_equal notice_annotation_check_run.name, loader_notice_annotation.check_run.name
          assert_equal warning_annotation_check_run.name, loader_warning_annotation.check_run.name
          assert_equal failure_annotation_check_run.name, loader_failure_annotation.check_run.name

          assert_equal notice_annotation_check_run.details_url, loader_notice_annotation.check_run.details_url
          assert_equal warning_annotation_check_run.details_url, loader_warning_annotation.check_run.details_url
          assert_equal failure_annotation_check_run.details_url, loader_failure_annotation.check_run.details_url

          assert_equal notice_annotation_check_run.check_suite.name, loader_notice_annotation.check_suite_name
          assert_equal warning_annotation_check_run.check_suite.name, loader_warning_annotation.check_suite_name
          assert_equal failure_annotation_check_run.check_suite.name, loader_failure_annotation.check_suite_name

          assert_equal @default_check_suite.github_app.preferred_avatar_url(size: 20), loader_notice_annotation.app_avatar_url
          assert_equal @default_check_suite.github_app.preferred_avatar_url(size: 20), loader_warning_annotation.app_avatar_url
          assert_equal @default_check_suite.github_app.preferred_avatar_url(size: 20), loader_failure_annotation.app_avatar_url

          assert_equal "#{@default_check_suite.github_app.name} avatar image", loader_notice_annotation.app_avatar_alt_text
          assert_equal "#{@default_check_suite.github_app.name} avatar image", loader_warning_annotation.app_avatar_alt_text
          assert_equal "#{@default_check_suite.github_app.name} avatar image", loader_failure_annotation.app_avatar_alt_text

          assert_equal notice_annotation.path.dup.force_encoding("UTF-8"), loader_notice_annotation.path
          assert_equal warning_annotation.path.dup.force_encoding("UTF-8"), loader_warning_annotation.path
          assert_equal failure_annotation.path.dup.force_encoding("UTF-8"), loader_failure_annotation.path

          assert_equal Digest::SHA256.hexdigest(notice_annotation.path), loader_notice_annotation.path_digest
          assert_equal Digest::SHA256.hexdigest(warning_annotation.path), loader_warning_annotation.path_digest
          assert_equal Digest::SHA256.hexdigest(failure_annotation.path), loader_failure_annotation.path_digest

          assert_equal notice_annotation.title.dup.force_encoding("UTF-8"), loader_notice_annotation.title
          assert_equal warning_annotation.title.dup.force_encoding("UTF-8"), loader_warning_annotation.title
          assert_equal failure_annotation.title.dup.force_encoding("UTF-8"), loader_failure_annotation.title

          assert_equal notice_annotation.global_relay_id, loader_notice_annotation.id
          assert_equal warning_annotation.global_relay_id, loader_warning_annotation.id
          assert_equal failure_annotation.global_relay_id, loader_failure_annotation.id

          assert_equal notice_annotation.id, loader_notice_annotation.database_id
          assert_equal warning_annotation.id, loader_warning_annotation.database_id
          assert_equal failure_annotation.id, loader_failure_annotation.database_id

          assert_equal notice_annotation.message.dup.force_encoding("UTF-8"), loader_notice_annotation.message
          assert_equal warning_annotation.message.dup.force_encoding("UTF-8"), loader_warning_annotation.message
          assert_equal failure_annotation.message.dup.force_encoding("UTF-8"), loader_failure_annotation.message
        end

        context ":app_avatar_url field" do
          test "has database error fallback" do
            annotation = create(:check_annotation,
              check_run: create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure),
              path: "app/packages/ui/types.ts",
              annotation_level: "failure",
              start_line: 5,
              end_line: 7
            )

            Integration.any_instance.stubs(:marketplace_listing).raises(ActiveRecord::ActiveRecordError.new)

            data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            assert_equal 1, data.size

            assert_equal ::User.ghost.primary_avatar_url(20), T.must(data.first).app_avatar_url
          end

          test "uses an integration marketplace listing logo if publicly listed" do
            annotation = create(:check_annotation,
              check_run: create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure),
              path: "app/packages/ui/types.ts",
              annotation_level: "failure",
              start_line: 5,
              end_line: 7
            )
            public_listing = create(:marketplace_listing, :verified)

            Integration.any_instance.stubs(:marketplace_listing).returns(public_listing)

            data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            assert_equal 1, data.size

            assert_equal public_listing.primary_avatar_url(40), T.must(data.first).app_avatar_url
          end
        end

        context ":app_avatar_alt_text field" do
          test "has database error fallback" do
            annotation = create(:check_annotation,
              check_run: create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure),
              path: "app/packages/ui/types.ts",
              annotation_level: "failure",
              start_line: 5,
              end_line: 7
            )

            Integration.any_instance.stubs(:name).raises(ActiveRecord::ActiveRecordError.new)

            data = PullRequests::PageData::Annotations::Loader.load(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
            assert_equal 1, data.size

            assert_equal "#{User.ghost.display_login} avatar image", T.must(data.first).app_avatar_alt_text
          end
        end

        test "load_annotation_levels_with_path returns expected data" do
          notice_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :success)
          warning_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)
          failure_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :failure)

          notice_annotation = create(
            :check_annotation,
            check_run: notice_annotation_check_run,
            path: "app/packages/ui/types.ts",
            annotation_level: "notice",
            start_line: 5,
            end_line: 7
          )
          warning_annotation = create(
            :check_annotation,
            check_run: warning_annotation_check_run,
            path: "app/packages/ui/tabs.spec.ts",
            annotation_level: "warning",
            start_line: 4,
            end_line: 6
          )
          failure_annotation = create(
            :check_annotation,
            check_run: failure_annotation_check_run,
            path: "app/packages/ui/spaces.spec.ts",
            annotation_level: "failure",
            start_line: 3,
            end_line: 5
          )

          data = PullRequests::PageData::Annotations::Loader.load_annotation_levels_with_path(pull_request: @pull, user_session: @user_session, current_user: @admin, end_commit_oid: @pull.head_sha)
          assert_equal 3, data.size

          loader_notice_annotation = T.must(data.find { |e| e.annotation_level == "notice" })
          loader_warning_annotation = T.must(data.find { |e| e.annotation_level == "warning" })
          loader_failure_annotation = T.must(data.find { |e| e.annotation_level == "failure" })

          assert_equal "app/packages/ui/types.ts", loader_notice_annotation.path
          assert_equal "app/packages/ui/tabs.spec.ts", loader_warning_annotation.path
          assert_equal "app/packages/ui/spaces.spec.ts", loader_failure_annotation.path
        end
      end
    end
  end
end
