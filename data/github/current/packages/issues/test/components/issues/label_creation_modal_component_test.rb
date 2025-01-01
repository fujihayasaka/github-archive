# typed: true
# frozen_string_literal: true

require "test_helper"

class Issues::LabelCreationModalComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @repo         = create(:repository, has_discussions: true)
    @issue        = create(:issue, repository: @repo)
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repo)
    @discussion   = create(:discussion, repository: @repo)
  end

  test "renders component for issue" do
    render_inline Issues::LabelCreationModalComponent.new(
      labelable: @issue,
      repository: @repo,
    )

    expected_path = "/#{@repo.nwo}/labels?return_label_list_item=issue"
    assert_selector("form[action='#{expected_path}']")
    assert_selector("input[name='context'][value='issue sidebar']", visible: false)
    assert_selector("input[name='issue_id'][value='#{@issue.id}']", visible: false)
  end

  test "renders component for pull request" do
    render_inline Issues::LabelCreationModalComponent.new(
      labelable: @pull_request.issue,
      repository: @repo,
    )

    expected_path = "/#{@repo.nwo}/labels?return_label_list_item=issue"
    assert_selector("form[action='#{expected_path}']")
    assert_selector("input[name='context'][value='pull request sidebar']", visible: false)
    assert_selector("input[name='issue_id'][value='#{@pull_request.issue.id}']", visible: false)
  end


  test "renders component for discussion" do
    render_inline Issues::LabelCreationModalComponent.new(
      labelable: @discussion,
      repository: @repo,
    )

    expected_path = "/#{@repo.nwo}/labels?return_label_list_item=discussion"
    assert_selector("form[action='#{expected_path}']")
    assert_selector("input[name='context'][value='discussion sidebar']", visible: false)
    refute_selector("input[name='issue_id']", visible: false)
  end
end
