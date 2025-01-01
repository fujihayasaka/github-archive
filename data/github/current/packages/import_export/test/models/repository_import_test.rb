# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryImportTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, name: "foobar", owner: @user)
    @import = create(:import, creator: @user)
  end

  context "validation" do
    test "is valid" do
      repository_import = RepositoryImport.new({ repository: @repo, import: @import })
      assert repository_import.valid?
    end

    test "fails when repository not passed in" do
      import = RepositoryImport.new({ import: @import })
      refute import.valid?

      assert_includes import.errors[:repository], "can't be blank"
    end

    test "fails when import not passed in" do
      import = RepositoryImport.new({ repository: @repo })
      refute import.valid?

      assert_includes import.errors[:import], "can't be blank"
    end
  end
end
