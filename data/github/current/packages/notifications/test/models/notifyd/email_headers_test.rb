# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class EmailHeadersTest < GitHub::TestCase
    context "build" do
      test "generates the correct default headers" do
        Timecop.freeze do
          issue = create(:issue)

          headers = EmailHeaders.new(issue, issue.repository, issue.user.display_login).build
          list_id = "#{issue.repository.name_with_display_owner} <#{issue.repository.name}.#{issue.repository.owner.display_login}.#{GitHub.urls.host_name}>"

          assert_equal headers, {
            "Message-ID": issue.message_id,
            "Precedence": "list",
            "Return-Path": "<#{GitHub.urls.noreply_address}>",
            "X-GitHub-Sender": issue.user.display_login,
            "List-Id": list_id,
            "List-Archive": issue.repository.permalink,
            "List-Post": GitHub.urls.noreply_address,
            "Date": Time.now.to_formatted_s(:rfc822)
          }
        end
      end

      context "with_in_reply_to" do
        test "adds the In-Reply-To and References fields" do
          issue_comment = create(:issue_comment)

          headers = EmailHeaders
          .new(issue_comment, issue_comment.repository, issue_comment.user.display_login)
          .with_in_reply_to(issue_comment.issue.message_id)
          .build

          assert_equal headers[:"In-Reply-To"], issue_comment.issue.message_id
          assert_equal headers[:"References"], issue_comment.issue.message_id
        end
      end

      context "with_reply_to" do
        test "adds the reply-to field" do
          check_suite = create(:check_suite)

          headers = EmailHeaders
          .new(check_suite, check_suite.repository, check_suite.creator)
          .with_reply_to("no-reply-address")
          .build

          assert_equal headers[:"Reply-To"], "no-reply-address"
        end
      end

      context "with_list_id" do
        test "adds custom list id field" do
          check_suite = create(:check_suite)

          headers = EmailHeaders
          .new(check_suite, check_suite.repository, check_suite.creator)
          .with_list_id("test-list-id")
          .build

          assert_equal headers[:"List-Id"], "test-list-id"
        end
      end

      context "with_list_archive" do
        test "adds the list archive field" do
          check_suite = create(:check_suite)

          headers = EmailHeaders
          .new(check_suite, check_suite.repository, check_suite.creator)
          .with_list_archive("test-list-archive")
          .build

          assert_equal headers[:"List-Archive"], "test-list-archive"
        end
      end
    end
  end
end
