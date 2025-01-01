# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#creator" do
    test "is valid" do
      import = Import.new({ creator: @user })
      assert import.valid?
    end

    test "fails when creator not passed in" do
      import = Import.new
      refute import.valid?

      assert_includes import.errors[:creator], "can't be blank"
    end
  end

  context "associations" do
    test "it can have many repositories" do
      import = create(:import)
      repository = create(:repository, name: "foobar", owner: @user)

      import.repositories << repository
      import.save!
      assert_includes import.repositories, repository
    end

    test "it can have many pull_requests" do
      import = create(:import)
      pull_request = create(:pull_request, :disable_disk_access)

      import.pull_requests << pull_request
      import.save!
      assert_includes import.pull_requests, pull_request
    end
  end
end
