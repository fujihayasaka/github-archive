# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotEngagedOssRepositoryTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "factory" do
    assert build(:copilot_engaged_oss_repository).valid?
  end
  test "validates" do
    copilot_engaged_oss_repository = Copilot::EngagedOssRepository.new

    refute copilot_engaged_oss_repository.valid?

    refute_nil copilot_engaged_oss_repository.errors[:fork_count]
    refute_nil copilot_engaged_oss_repository.errors[:language_name]
    refute_nil copilot_engaged_oss_repository.errors[:last_pushed_at]
    refute_nil copilot_engaged_oss_repository.errors[:license_id]
    refute_nil copilot_engaged_oss_repository.errors[:rank]
    refute_nil copilot_engaged_oss_repository.errors[:repository]
    refute_nil copilot_engaged_oss_repository.errors[:stargazer_count]

    copilot_engaged_oss_repository.repository = create(:public_repository, name: "public-repo-1")
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.fork_count = 1
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.language_name = create(:ruby_language_name)
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.last_pushed_at = 2.months.ago
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.license_id = 420 # not a valid license id
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.rank = 1
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.stargazer_count = 1
    refute copilot_engaged_oss_repository.valid?
    copilot_engaged_oss_repository.license_id = 1 # valid license id
    assert copilot_engaged_oss_repository.valid?
  end
end if GitHub.copilot_enabled?
