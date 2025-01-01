# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Icons
    class OcticonTest < GitHub::TestCase
      test "has a type" do
        icon = Octicon.new(name: "hubot")
        assert_equal :octicon, icon.type
      end

      test "has a name" do
        icon = Octicon.new(name: "hubot")
        assert icon.name.is_a?(String)
        assert_equal "hubot", icon.name
      end

      test "has an id" do
        icon = Octicon.new(name: "hubot")
        assert icon.id.is_a?(String)
        assert_equal "hubot-color-fg-muted", icon.id
      end

      test "doesn't raise when #as_json is invoked" do
        icon = Octicon.new(name: "hubot")
        assert icon.as_json.is_a?(Hash)
      end

      test "as_json structure" do
        icon = Octicon.new(name: "hubot")
        expected = {
          type: :octicon,
          id: "hubot-color-fg-muted"
        }
        assert_equal expected, icon.as_json
      end

      context ".for" do
        test "returns a default icon when given an unexpected object" do
          assert_equal Octicon.for(Object.new), Octicon.default_icon
        end

        test "returns icon appropriate to state when given an issue" do
          open_issue = build(:issue, state: :open)
          closed_issue = build(:issue, state: :closed)

          assert_equal Octicon.for(open_issue), Octicon.issue_open
          assert_equal Octicon.for(closed_issue), Octicon.issue_closed
        end

        test "returns icon appropriate to state when given a pull request" do
          open_pull_request = create(:pull_request, :disable_disk_access)
          closed_pull_request = create(:pull_request, :disable_disk_access, :closed)
          merged_pull_request = create(:pull_request, :disable_disk_access, :merged)

          assert_equal Octicon.for(open_pull_request), Octicon.git_pull_request_open
          assert_equal Octicon.for(closed_pull_request), Octicon.git_pull_request_closed
          assert_equal Octicon.for(merged_pull_request), Octicon.git_pull_request_merged
        end

        test "returns icon appropriate to state when given a pull request's issue" do
          open_pull_request = create(:pull_request, :disable_disk_access)
          closed_pull_request = create(:pull_request, :disable_disk_access, :closed)
          merged_pull_request = create(:pull_request, :disable_disk_access, :merged)

          assert_equal Octicon.for(open_pull_request.issue), Octicon.git_pull_request_open
          assert_equal Octicon.for(closed_pull_request.issue), Octicon.git_pull_request_closed
          assert_equal Octicon.for(merged_pull_request.issue), Octicon.git_pull_request_merged
        end

        test "returns icon appropriate to repository visibility" do
          repo = build(:repository)
          private_repo = build(:repository, :private)

          assert_equal Octicon.for(repo), Octicon.new(name: "repo")
          assert_equal Octicon.for(private_repo), Octicon.private_repo
        end

        test "returns icon appropriate for open discussion" do
          discussion = build(:discussion)
          octicon = Octicon.for(discussion)
          assert_equal "comment-discussion", octicon.name
          assert_equal "color-fg-muted", octicon.classes
        end

        Closables::BaseComponent::DISCUSSION_REASONS.each do |reason|
          test "returns icon appropriate for closed discussion as #{reason.value}" do
            discussion = build(:discussion, state: :closed, state_reason: reason.value)
            octicon = Octicon.for(discussion)
            assert_equal reason.octicon, octicon.name
            assert_equal "color-fg-#{reason.octicon_color}", octicon.classes
          end
        end
      end
    end
  end
end
