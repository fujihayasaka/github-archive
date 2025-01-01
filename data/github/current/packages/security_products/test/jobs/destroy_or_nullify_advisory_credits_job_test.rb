# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DestroyOrNullifyAdvisoryCreditsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @vulnerability = create(:published_vulnerability)
    @repository_advisory = create(:published_repository_advisory)
    @repo_advisory_credit = create(:advisory_credit,
      repository_advisory: @repository_advisory)
    @shared_credit = create(:advisory_credit,
      repository_advisory: @repository_advisory,
      vulnerability: @vulnerability)
  end

  test "destroys advisory credits that are not associated with a global advisory" do
    assert_changes -> { AdvisoryCredit.count }, from: 2, to: 1 do
      DestroyOrNullifyAdvisoryCreditsJob.perform_now(@repository_advisory.id)
    end

    assert_nil AdvisoryCredit.find_by(id: @repo_advisory_credit.id)
  end

  test "nullifies advisory credits that are associated with a global advisory" do
    assert_changes -> { @shared_credit.reload.repository_advisory }, from: @repository_advisory, to: nil do
      DestroyOrNullifyAdvisoryCreditsJob.perform_now(@repository_advisory.id)
    end
  end
end
