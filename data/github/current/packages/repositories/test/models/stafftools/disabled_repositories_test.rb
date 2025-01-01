# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::DisabledRepositoriesTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create :user
    @staff = create :staff_admin_user
    @repo1 = create :repository, owner: @user
    @repo2 = create :repository, owner: @user
    @url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  context "DisabledRepositories", skip_enterprise: true do
    test "#dmca_takedowns returns DMCA takedown events" do
      with_es_refresh(audit_log_search_index) do
        @repo1.access.disable("dmca", @staff, dmca_takedown: @url)
        @repo2.access.disable("dmca", @staff, dmca_takedown: @url)
      end

      results = Stafftools::DisabledRepositories.dmca_takedowns(@user)
      assert_equal 2, results.size
      assert_equal results.last[:repo], @repo1.nwo
    end
  end
end
