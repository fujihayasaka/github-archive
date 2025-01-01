# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityOverviewAnalytics::RepositoryTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @biz = if GitHub.enterprise?
      create(:global_business)
    else
      create(:business, :enterprise_managed)
    end

    @user = if GitHub.enterprise?
      create(:user, business: @biz)
    else
      create(:emu, business: @biz)
    end

    @org = create(:business_plus_organization, business: @biz)
    @org_repo = create(:repository, owner: @org)
    @org_repo_metadata_by_bot = create(:soa_repository, repository: @org_repo)

    @user_repo = create(:repository, owner: @user)
    @user_repo_metadata_by_bot = create(:soa_repository, repository: @user_repo)
  end

  context "#factorybot" do
    test "can create data with defaults" do
      by_model = SecurityOverviewAnalytics::Repository.find_by!(repository_id: @org_repo_metadata_by_bot.repository_id)
      assert_equal by_model, @org_repo_metadata_by_bot
    end
  end

  context "#relations" do
    test "can access repository record" do
      by_model = SecurityOverviewAnalytics::Repository.find_by!(repository_id: @org_repo_metadata_by_bot.repository_id)
      repository = ::Repositories::Public.get_active_or_deleted!(T.must(by_model.repository_id))
      assert_equal repository, by_model.repository
    end

    test "can access organization record" do
      by_model = SecurityOverviewAnalytics::Repository.find_by!(repository_id: @org_repo_metadata_by_bot.repository_id)
      organization = ::Organization.find_by!(id: by_model.organization_id)
      assert_equal organization, by_model.organization
    end

    test "can access SecurityOverviewAnalytics::FeatureStatusRevision records" do
      date_id = SecurityOverviewAnalytics::Date.id_from_time(Time.now)
      revision1 = create(:security_overview_analytics_feature_status_revision, repository_metadata: @org_repo_metadata_by_bot, date_id: date_id - 1, next_revision_date_id: date_id)
      revision2 = create(:security_overview_analytics_feature_status_revision, repository_metadata: @org_repo_metadata_by_bot, date_id: date_id, next_revision_date_id: 99991231)
      assert_equal [revision1, revision2], @org_repo_metadata_by_bot.feature_status_revisions.order(:id).to_a
    end
  end

  context "#visibility" do
    test "sets and returns enum value" do
      private_repo = create(:private_repository, owner: @org)
      repo_data = create(:security_overview_analytics_repository, repository: private_repo)
      assert repo_data.private?
      assert_equal "private", repo_data.visibility

      repo_data.visibility = :public
      repo_data.save!
      repo_data = T.must(SecurityOverviewAnalytics::Repository.find_by(repository_id: repo_data.repository_id))
      assert repo_data.public?
      assert_equal "public", repo_data.visibility

      repo_data.internal!
      repo_data = T.must(SecurityOverviewAnalytics::Repository.find_by(repository_id: repo_data.repository_id))
      assert repo_data.internal?
      assert_equal "internal", repo_data.visibility
    end

    test "sets and returns properly with repository visibility data" do
      # This test verified the compatibility with existing visibility value from repositories
      Repository::VISIBILITIES.each do |visibility|
        repo = create(:repository, owner: @org)
        repo_data = create(
          :security_overview_analytics_repository,
          repository: repo,
          visibility: visibility
        )
        assert_equal(
          visibility,
          repo_data.visibility,
          "SecurityOverviewAnalytics::Repository contains unexpected visibility mappings. Please verify and update the data model accordingly."
        )
      end
    end

    test "returns nil for unexpected enum value from datatable" do
      private_repo = create(:private_repository, owner: @org)
      repo_data = create(:security_overview_analytics_repository, repository: private_repo)
      assert repo_data.private?

      SecurityOverviewAnalytics::Repository.where(
        repository_id: repo_data.repository_id,
        visibility: :private
      ).update_all(visibility: 9)
      assert_nil repo_data.reload.visibility
    end

    test "raises ArgumentError when set with unknown value" do
      private_repo = create(:private_repository, owner: @org)
      repo_data = create(:security_overview_analytics_repository, repository: private_repo)
      assert repo_data.private?
      assert_raises ArgumentError do
        repo_data.visibility = "hmm"
      end
    end
  end

  context "#fields_with_deviation" do
    test "returns empty array if there is no deviation" do
      assert @org_repo_metadata_by_bot.fields_with_deviation.empty?
    end

    test "returns repo_not_found if repository is not found" do
      @org_repo_metadata_by_bot.repository.destroy
      assert_equal :repo_not_found, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
    end

    test "returns repo_deleted if repository is not found" do
      @org_repo_metadata_by_bot.repository.remove(create(:user))
      assert_equal :repo_deleted, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
    end

    test "returns business_id field if repository has different business compared to business_id" do
      @org_repo_metadata_by_bot.update(business_id: nil)
      deviations = @org_repo_metadata_by_bot.reload.fields_with_deviation
      assert_includes(deviations, :business_id)
    end

    test "returns organization_id field if repository has different owner compared to organization_id" do
      org = create :organization
      @org_repo.update(owner_id: org.id)
      deviations = @org_repo_metadata_by_bot.reload.fields_with_deviation
      assert_includes(deviations, :organization_id)
    end

    test "returns owner_id field if repository has different owner compared to owner_id" do
      org = create :organization
      @org_repo.update(owner_id: org.id)
      deviations = @org_repo_metadata_by_bot.reload.fields_with_deviation
      assert_includes(deviations, :owner_id)
    end

    test "returns owner_type field if repository has different owner type" do
      @user_repo.update(owner_id: @org.id)
      deviations = @user_repo_metadata_by_bot.reload.fields_with_deviation
      assert_includes(deviations, :owner_type)
    end

    test "returns name field if repository has different name" do
      @org_repo_metadata_by_bot.repository.update(name: "oops")
      assert_equal :name, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
    end

    test "returns archived field if repository has different archived state" do
      @org_repo_metadata_by_bot.repository.set_archived
      assert_equal :archived, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
    end

    test "returns visibility field if repository has different visibility" do
      @org_repo_metadata_by_bot.repository.set_permission(:private)
      assert_equal :visibility, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
    end

    context "pushed_at" do
      test "returns pushed_at if timestamps are more than one minute apart" do
        pushed_at = Time.current
        @org_repo_metadata_by_bot.repository.update(pushed_at:)
        @org_repo_metadata_by_bot.update(pushed_at: pushed_at - 61.seconds)
        assert_equal :pushed_at, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
      end

      test "returns nothing if timestamps are within one minute" do
        pushed_at = Time.current
        @org_repo_metadata_by_bot.repository.update(pushed_at:)
        @org_repo_metadata_by_bot.update(pushed_at: pushed_at - 59.seconds)
        assert_equal :pushed_at, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
      end

      test "returns pushed_at if we don't have a value" do
        @org_repo_metadata_by_bot.repository.update(pushed_at: Time.current)
        @org_repo_metadata_by_bot.update(pushed_at: nil)
        assert_equal :pushed_at, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
      end

      test "returns pushed_at if source doesn't have a value" do
        @org_repo_metadata_by_bot.repository.update(pushed_at: nil)
        @org_repo_metadata_by_bot.update(pushed_at: Time.current)
        assert_equal :pushed_at, @org_repo_metadata_by_bot.reload.fields_with_deviation.first
      end
    end
  end

  context "#delete_by_repository_ids" do
    test "deletes all revisions on a repository" do
      repo1 = create(:repository, owner: @org)
      create(:security_overview_analytics_repository, repository: repo1)
      repo2 = create(:repository, owner: @org)
      create(:security_overview_analytics_repository, repository: repo2)
      repo3 = create(:repository, owner: @org)
      create(:security_overview_analytics_repository, repository: repo3)

      refute_empty SecurityOverviewAnalytics::Repository.where(repository_id: repo1.id).to_a
      refute_empty SecurityOverviewAnalytics::Repository.where(repository_id: repo2.id).to_a
      refute_empty SecurityOverviewAnalytics::Repository.where(repository_id: repo3.id).to_a

      SecurityOverviewAnalytics::Repository.delete_by_repository_ids([repo1.id, repo2.id])

      assert_empty SecurityOverviewAnalytics::Repository.where(repository_id: [repo1.id, repo2.id]).to_a
      assert_dogstats_count_value 2, "security_overview_analytics.repository_metadata.deleted"

      refute_empty SecurityOverviewAnalytics::Repository.where(repository_id: repo3.id).to_a
    end
  end

  context "#timestamps" do
    test "are stored in utc" do
      now = Time.now
      model = create(:security_overview_analytics_repository, event_time: now, created_at: now, updated_at: now)
      assert model.event_time.utc?
      assert_timestamp now.utc, model.event_time
      assert model.created_at&.utc?
      assert_timestamp now.utc, model.created_at
      assert model.updated_at&.utc?
      assert_timestamp now.utc, model.updated_at
    end
  end

  private def assert_timestamp(expected, actual)
    assert_equal expected.year, actual.year
    assert_equal expected.month, actual.month
    assert_equal expected.day, actual.day
    assert_equal expected.hour, actual.hour
    assert_equal expected.min, actual.min
    assert_equal expected.sec, actual.sec
    assert_equal expected.usec, actual.usec
  end
end
