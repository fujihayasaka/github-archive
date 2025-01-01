# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::LanguageRepositoryLoaderTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper

  fixtures do
    @ruby = create(:language_name, name: "Ruby", linguist_id: 326)
  end

  context "perform" do
    test "it deletes the existing records" do
      GitHub.flipper[:copilot_engaged_oss_job].enable
      license = License.find("mit")
      repos = Array.new
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      1.upto(3).each do |i|
        org = create(:business_plus_organization)
        other_public_repo = create(:repository, primary_language: @ruby, owner: org, created_at: 2.months.ago, stargazer_count: 5002 + i, public_fork_count: 26 + i)
        other_public_repo.update_attribute(:public_fork_count, 26)
        create(:repository_license, repository: other_public_repo, license_id: license.id)
        repos << other_public_repo
      end

      to_be_deleted = create(:copilot_engaged_oss_repository, language_name: @ruby, repository: create(:repository), rank: 1)
      create(:copilot_engaged_oss_repository, language_name: @ruby, repository: repos.first, rank: 2)

      assert_performed_jobs 3, only: Copilot::EngagedOssRepositoryUserJob do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Deleting existing records") do
            Copilot::LanguageRepositoryLoader.call(language_name: @ruby)
          end
        end
      end

      # this should be deleted because it got bumped
      refute Copilot::EngagedOssRepository.exists?(to_be_deleted.id)

      repos.each do |repo|
        assert Copilot::EngagedOssRepository.exists?(repository_id: repo.id)
      end
      assert_equal 1, GitHub.dogstats.histograms("copilot.engaged_oss_repository.churn").count
    end

    test "it ranks things correctly" do
      license = License.find("mit")
      repos = Array.new

      1.upto(3).each do |i|
        org = create(:business_plus_organization)
        other_public_repo = create(:repository, primary_language: @ruby, owner: org, created_at: 2.months.ago, stargazer_count: 5002 + i, public_fork_count: 26 + i)
        other_public_repo.update_attribute(:public_fork_count, 26 + i)
        create(:repository_license, repository: other_public_repo, license_id: license.id)
        repos << other_public_repo
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::LanguageRepositoryLoader.call(language_name: @ruby)
      end

      repo_ids = repos.reverse.map(&:id)
      engaged_ids = Copilot::EngagedOssRepository.all.order(:rank).map(&:repository_id)
      assert_equal repo_ids, engaged_ids
    end
  end
end if GitHub.copilot_enabled?
