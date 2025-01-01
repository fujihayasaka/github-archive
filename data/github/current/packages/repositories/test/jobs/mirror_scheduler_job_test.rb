# typed: strict
# frozen_string_literal: true

require "test_helper"

class MirrorSchedulerJobTest < GitHub::TestCase
  test "works in multi-tenant enterprise" do
    on_multi_tenant_enterprise do
      owner = create(:emu)
      business = owner.enterprise_managed_business
      member = create(:emu, business: business)
      organization = create(:organization, admin: owner)
      mirror = create(:mirror_repository, owner: organization)

      MirrorSchedulerJob.perform_now
    end

    assert_enqueued_jobs 1, only: RepositoryMirrorJob
  end
end
