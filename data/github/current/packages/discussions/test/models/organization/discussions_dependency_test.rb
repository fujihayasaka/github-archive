# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDiscussionsDependencyTest < GitHub::TestCase
  fixtures do
    @org_discussions_config = create(:organization_discussion_config)
    @org = @org_discussions_config.organization
  end

  context "discussion_repository" do
    test "destroys record when organization is destroyed" do
      @org.destroy!
      assert_nil OrganizationDiscussionConfig.find_by(organization_id: @org.id)
    end
  end
end
