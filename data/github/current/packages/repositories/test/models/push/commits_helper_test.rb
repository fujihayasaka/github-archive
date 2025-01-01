

# typed: true
# frozen_string_literal: true

require "test_helper"

class Pushes::CommitsHelperTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :post_receive_job_test)
  end

  setup do
    @commits_helper = Class.new do
      include Pushes::CommitsHelper
      attr_accessor :before, :after, :ref, :repository
      def initialize(repo)
        @repository = repo
        @before = GitHub::NULL_OID
        @after = "3c2644823caa63b9de90e80872d6c6ab0fd13c01"
        @ref = "refs/heads/master"
      end
    end.new(@repo)
  end

  context "#commits_pushed_limited" do
    test "limits pushes" do
      assert_equal 4, @commits_helper.commits_pushed.count
      assert_equal @commits_helper.commits_pushed, @commits_helper.commits_pushed_limited

      Pushes::CommitsHelper.stub_const(:LARGE_PUSH_THRESHOLD, 1) do
        assert_equal 0, @commits_helper.commits_pushed_limited.count
        assert_equal [], @commits_helper.commits_pushed_limited
      end
    end
  end

  test "calculating unique commits on new branch pushes" do
    @commits_helper.ref    = "refs/heads/topic-fast-forward"
    @commits_helper.before = GitHub::NULL_OID
    @commits_helper.after  = "e5d54f3fd3a8d7bf301a8c07f9ec579fc5457214"
    assert @commits_helper.created?
    refute @commits_helper.deleted?
    assert_equal 2, @commits_helper.commits_pushed_count
    assert_equal %w[
      998f30046bf6c8e662901861e299e8c2f22afa6a
      e5d54f3fd3a8d7bf301a8c07f9ec579fc5457214
    ], @commits_helper.commits_pushed.map(&:oid)
  end

  test "determining commit list on force pushes" do
    @commits_helper.ref    = "refs/heads/topic-force-push"
    @commits_helper.before = "63611721afd41f58f801d66e543d8288b4c5eb44"
    @commits_helper.after  = "02d44624a600ee7afd17785327a5cbc59b2e0571"

    refute @commits_helper.created?
    refute @commits_helper.deleted?
    assert_equal true, @commits_helper.non_fast_forward?
    assert_equal "c1800491d95c42b4e96fb83f31fe8d9230c62907", @commits_helper.merge_base_commit_sha
    assert_equal 3, @commits_helper.commits_pushed_count
    assert_equal %w[
      7131329d0834e23c2e1c7e73234b1c8381af9a80
      db1296776ed3577724033671af8b10ef8b402ef1
      02d44624a600ee7afd17785327a5cbc59b2e0571
    ], @commits_helper.commits_pushed.map(&:oid)
  end
end
