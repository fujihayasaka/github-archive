# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module CommitComments
      class PayloadTest < GitHub::TestCase
        test "call groups comments by path and position" do
          comments = [
            Loader::Comment.new(
              id: 1,
              relay_id: "relay1",
              body: "Comment 1",
              html_body: "<p>Comment 1</p>",
              body_version: "yeah",
              created_at: Time.zone.now,
              updated_at: Time.zone.now,
              last_user_content_edit: nil,
              path: "file1.rb",
              position: 1,
              is_hidden: false,
              viewer_can_minimize: true,
              minimized_reason: nil,
              viewer_can_delete: true,
              viewer_can_update: true,
              viewer_can_report: true,
              viewer_can_report_to_maintainer: true,
              viewer_can_block_from_org: true,
              viewer_can_unblock_from_org: true,
              viewer_did_author: true,
              url_fragment: "fragment1",
              viewer_can_read_user_content_edits: true,
              author: Loader::Author.new(id: 1, display_login: "user1", avatar_url: "avatar1"),
              author_association: :OWNER,
              thread_id: "thread1"
            ),
            Loader::Comment.new(
              id: 2,
              relay_id: "relay2",
              body: "Comment 2",
              html_body: "<p>Comment 2</p>",
              body_version: "yeah",
              created_at: Time.zone.now,
              updated_at: Time.zone.now,
              last_user_content_edit: nil,
              path: "file1.rb",
              position: 1,
              is_hidden: false,
              viewer_can_minimize: true,
              minimized_reason: nil,
              viewer_can_delete: true,
              viewer_can_update: true,
              viewer_can_report: true,
              viewer_can_report_to_maintainer: true,
              viewer_can_block_from_org: true,
              viewer_can_unblock_from_org: true,
              viewer_did_author: true,
              url_fragment: "fragment2",
              viewer_can_read_user_content_edits: true,
              author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
              author_association: :OWNER,
              thread_id: "thread2"
            ),
            Loader::Comment.new(
              id: 3,
              relay_id: "relay2",
              body: "Comment 2",
              html_body: "<p>Comment 3</p>",
              body_version: "yeah",
              created_at: Time.zone.now,
              updated_at: Time.zone.now,
              last_user_content_edit: nil,
              path: "file2.rb",
              position: 3,
              is_hidden: false,
              viewer_can_minimize: true,
              minimized_reason: nil,
              viewer_can_delete: true,
              viewer_can_update: true,
              viewer_can_report: true,
              viewer_can_report_to_maintainer: true,
              viewer_can_block_from_org: true,
              viewer_can_unblock_from_org: true,
              viewer_did_author: true,
              url_fragment: "fragment2",
              viewer_can_read_user_content_edits: true,
              author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
              author_association: :OWNER,
              thread_id: "thread2"
            ),
            Loader::Comment.new(
              id: 4,
              relay_id: "relay2",
              body: "Comment 2",
              html_body: "<p>Comment 4</p>",
              body_version: "yeah",
              created_at: Time.zone.now,
              updated_at: Time.zone.now,
              last_user_content_edit: nil,
              path: "file2.rb",
              position: 1,
              is_hidden: false,
              viewer_can_minimize: true,
              minimized_reason: nil,
              viewer_can_delete: true,
              viewer_can_update: true,
              viewer_can_report: true,
              viewer_can_report_to_maintainer: true,
              viewer_can_block_from_org: true,
              viewer_can_unblock_from_org: true,
              viewer_did_author: true,
              url_fragment: "fragment2",
              viewer_can_read_user_content_edits: true,
              author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
              author_association: :OWNER,
              thread_id: "thread2"
            ),
            Loader::Comment.new(
              id: 5,
              relay_id: "relay2",
              body: "Comment 2",
              html_body: "<p>Comment 5</p>",
              body_version: "yeah",
              created_at: Time.zone.now,
              updated_at: Time.zone.now,
              last_user_content_edit: nil,
              path: "file2.rb",
              position: 1,
              is_hidden: false,
              viewer_can_minimize: true,
              minimized_reason: nil,
              viewer_can_delete: true,
              viewer_can_update: true,
              viewer_can_report: true,
              viewer_can_report_to_maintainer: true,
              viewer_can_block_from_org: true,
              viewer_can_unblock_from_org: true,
              viewer_did_author: true,
              url_fragment: "fragment2",
              viewer_can_read_user_content_edits: true,
              author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
              author_association: :OWNER,
              thread_id: "thread2"
            )
          ]

          result = Payload.call(comments)

          assert_equal 1, result["file1.rb"]&.size
          assert_equal 2, T.must(result["file1.rb"])[1]&.size
          assert_equal 2, result["file2.rb"]&.size
          assert_equal 2, T.must(result["file1.rb"])[1]&.size
        end

        test "build_author returns nil if author is nil" do
          payload = Payload.new
          assert_nil payload.send(:build_author, nil)
        end

        test "comment is transformed into proper payload value" do
          payload = Payload.new
          comment = Loader::Comment.new(
            id: 1,
            relay_id: "relay1",
            body: "Comment 1",
            html_body: "<p>Comment 1</p>",
            body_version: "yeah",
            created_at: Time.zone.now,
            updated_at: Time.zone.now,
            last_user_content_edit: nil,
            path: "file1.rb",
            position: 1,
            is_hidden: false,
            viewer_can_minimize: true,
            minimized_reason: nil,
            viewer_can_delete: true,
            viewer_can_update: true,
            viewer_can_report: true,
            viewer_can_report_to_maintainer: true,
            viewer_can_block_from_org: true,
            viewer_can_unblock_from_org: true,
            viewer_did_author: true,
            url_fragment: "fragment1",
            viewer_can_read_user_content_edits: true,
            author: Loader::Author.new(id: 1, display_login: "user1", avatar_url: "avatar1"),
            author_association: :OWNER,
            thread_id: "thread1"
          )

          transformed_comment = payload.send(:call, [comment]).values.flatten.first.values.flatten.first

          assert_equal comment.id, transformed_comment.id
          assert_equal comment.relay_id, transformed_comment.relayId
          assert_equal comment.body, transformed_comment.body
          assert_equal comment.html_body, transformed_comment.htmlBody
          assert_equal comment.created_at, transformed_comment.createdAt
          assert_equal comment.updated_at, transformed_comment.updatedAt
          assert_nil transformed_comment.lastUserContentEdit
          assert_equal comment.path, transformed_comment.path
          assert_equal comment.position, transformed_comment.position
          assert_equal comment.is_hidden, transformed_comment.isHidden
          assert_equal comment.viewer_can_minimize, transformed_comment.viewerCanMinimize
          assert_nil transformed_comment.minimizedReason
          assert_equal comment.viewer_can_delete, transformed_comment.viewerCanDelete
          assert_equal comment.viewer_can_update, transformed_comment.viewerCanUpdate
          assert_equal comment.viewer_can_report, transformed_comment.viewerCanReport
          assert_equal comment.viewer_can_report_to_maintainer, transformed_comment.viewerCanReportToMaintainer
          assert_equal comment.viewer_can_block_from_org, transformed_comment.viewerCanBlockFromOrg
          assert_equal comment.viewer_can_unblock_from_org, transformed_comment.viewerCanUnblockFromOrg
          assert_equal comment.viewer_did_author, transformed_comment.viewerDidAuthor
          assert_equal comment.url_fragment, transformed_comment.urlFragment
          assert_equal comment.viewer_can_read_user_content_edits, transformed_comment.viewerCanReadUserContentEdits
          assert_equal comment.author&.id.to_s, transformed_comment.author.id
          assert_equal comment.author&.display_login, transformed_comment.author.login
          assert_equal comment.author&.avatar_url, transformed_comment.author.avatarUrl
          assert_equal comment.author_association, transformed_comment.authorAssociation
          assert_equal comment.thread_id, transformed_comment.threadId
        end

        test "build_author returns Author object if author is present" do
          payload = Payload.new
          author_snake = Loader::Author.new(id: 1, display_login: "user1", avatar_url: "avatar1")
          author = payload.send(:build_author, author_snake)

          assert_equal "1", author.id
          assert_equal "user1", author.login
          assert_equal "avatar1", author.avatarUrl
        end

        test "build_last_edit returns nil if last_user_content_edit is nil" do
          payload = Payload.new
          comment = Loader::Comment.new(
            id: 5,
            relay_id: "relay2",
            body: "Comment 2",
            html_body: "<p>Comment 5</p>",
            body_version: "yeah",
            created_at: Time.zone.now,
            updated_at: Time.zone.now,
            last_user_content_edit: nil,
            path: "file2.rb",
            position: 1,
            is_hidden: false,
            viewer_can_minimize: true,
            minimized_reason: nil,
            viewer_can_delete: true,
            viewer_can_update: true,
            viewer_can_report: true,
            viewer_can_report_to_maintainer: true,
            viewer_can_block_from_org: true,
            viewer_can_unblock_from_org: true,
            viewer_did_author: true,
            url_fragment: "fragment2",
            viewer_can_read_user_content_edits: true,
            author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
            author_association: :OWNER,
            thread_id: "thread2"
          )
          assert_nil payload.send(:build_last_edit, comment)
        end

        test "build_last_edit returns LastContentEdit object if last_user_content_edit is present" do
          payload = Payload.new
          editor = create(:user)
          last_edit = Loader::UserContentEdit.new(id: "edit1", editor: editor)
          comment = Loader::Comment.new(
            id: 5,
            relay_id: "relay2",
            body: "Comment 2",
            html_body: "<p>Comment 5</p>",
            body_version: "yeah",
            created_at: Time.zone.now,
            updated_at: Time.zone.now,
            last_user_content_edit: last_edit,
            path: "file2.rb",
            position: 1,
            is_hidden: false,
            viewer_can_minimize: true,
            minimized_reason: nil,
            viewer_can_delete: true,
            viewer_can_update: true,
            viewer_can_report: true,
            viewer_can_report_to_maintainer: true,
            viewer_can_block_from_org: true,
            viewer_can_unblock_from_org: true,
            viewer_did_author: true,
            url_fragment: "fragment2",
            viewer_can_read_user_content_edits: true,
            author: Loader::Author.new(id: 2, display_login: "user2", avatar_url: "avatar2"),
            author_association: :OWNER,
            thread_id: "thread2"
          )

          last_content_edit = payload.send(:build_last_edit, comment)

          assert_equal "edit1", last_content_edit.id
          assert_equal editor.display_login, last_content_edit.editor.login
          assert_equal editor.primary_avatar_url, last_content_edit.editor.avatarUrl
        end
      end
    end
  end
end
