# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestImportTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @pull_request = create(:pull_request, :disable_disk_access)
    @import = create(:import, creator: @user)
  end

  context "validation" do
    test "is valid" do
      pull_request_import = PullRequestImport.new({ pull_request: @pull_request, import: @import })

      assert pull_request_import.valid?
    end

    test "fails when pull request not passed in" do
      pull_request_import = PullRequestImport.new({ import: @import })
      refute pull_request_import.valid?

      assert_includes pull_request_import.errors[:pull_request], "can't be blank"
    end

    test "fails when import not passed in" do
      pull_request_import = PullRequestImport.new({ pull_request: @pull_request })
      refute pull_request_import.valid?

      assert_includes pull_request_import.errors[:import], "can't be blank"
    end
  end
end
