# typed: true
# frozen_string_literal: true

require "test_helper"

class BlobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  context "#peel_to_commit" do
    test "it is always nil" do
      tree = @repo.objects.read(@repo.default_branch_ref.target.tree_oid)
      first_blob_entry = tree.entries.find(&:blob?)
      blob = @repo.objects.read(first_blob_entry.oid)
      assert_nil(blob.peel_to_commit)
    end
  end
end
