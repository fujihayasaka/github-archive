# typed: true
# frozen_string_literal: true

require "test_helper"

class ToggleFailoverJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "it rejects resumes and creates" do
    stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

    Codespaces::ToggleFailoverJob.perform_now(
      region: stamp.region.id,
      vscs_target: :production,
      redirect: true, only: nil,
      codespaces_repository: create(:repository),
      actor: nil
    )

    refute stamp.available_for_resumes?(user: @user)
    refute stamp.available_for_creates?(user: @user)
  end

  test "it restores resumes and creates" do
    stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
    stamp.failover

    Codespaces::ToggleFailoverJob.perform_now(
      region: stamp.region.id,
      vscs_target: :production,
      redirect: false,
      only: nil,
      codespaces_repository: create(:repository),
      actor: nil
    )

    assert stamp.available_for_resumes?(user: @user)
    assert stamp.available_for_creates?(user: @user)
  end
end
