# typed: true
# frozen_string_literal: true

require "test_helper"

class TreeTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  context "#peel_to_commit" do
    test "it is always nil!" do
      tree = @repo.objects.read(@repo.default_branch_ref.target.tree_oid)
      assert_nil(tree.peel_to_commit)
    end
  end
end
