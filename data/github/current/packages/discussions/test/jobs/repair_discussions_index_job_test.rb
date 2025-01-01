# typed: true
# frozen_string_literal: true

require "test_helper"

class RepairDiscussionsIndexTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @github_org = create(:organization, login: "github")
  end

  setup do
    @index = Elastomer::Indexes::Discussions.new
    @index_name = @index.name
    @cluster_name = ::Elastomer.router.cluster_for_index(@index_name)
    @repair_job = RepairDiscussionsIndexJob.new(@index_name, { cluster: @cluster_name })
    @repair_job.reset!
  end

  context "db lookup" do
    test "ignores discussions orphaned by a deleted repository" do
      repo = create(:repository, organization: @github_org, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      orphaned_discussion = create(:discussion, repository: repo).update_attribute(:repository_id, 1234567890)

      models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

      assert_equal [discussion.id], models
    end

    test "ignores discussions with a category id that no longer exists" do
      repo = create(:repository, organization: @github_org, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      orphaned_discussion = create(:discussion, repository: repo).update_attribute(:discussion_category_id, 1234567890)

      models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

      assert_equal [discussion.id], models
    end
  end
end
