# typed: true
# frozen_string_literal: true

require "test_helper"

class RegistryPackagesMigrationTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @migration_run = create(:packages_migration, owner: @owner, total_org_count: 20, total_pkg_count: 100,  state: :inProgress)
    if GitHub.enterprise?
      @business = create(:global_business)
    end
  end

  context "table operations for Packages Migration" do
    test "verify the added record is valid" do
      assert_predicate @migration_run, :valid?
    end

    test "verify default value for success_org_count is 0" do
      assert_equal 0, @migration_run.success_org_count
    end

    test "verify default value for failed_org_count is 0" do
      assert_equal 0, @migration_run.failed_org_count
    end

    test "verify default value for success_pkg_count is 0" do
      assert_equal 0, @migration_run.success_pkg_count
    end

    test "verify default value for failed_pkg_count is 0" do
      assert_equal 0, @migration_run.failed_pkg_count
    end

    test "update state to complete" do
      @migration_run.update(state: :completed)
      assert_predicate @migration_run, :valid?
      assert_equal "completed", @migration_run.state
    end

    test "must have an owner" do
      @migration_run.update(owner: nil)
      refute_predicate @migration_run, :valid?
    end

    if GitHub.enterprise?
      test "test send email when migration completes" do
        ActionMailer::Base.deliveries.clear

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          migration_run_2 = create(:packages_migration, owner: @owner, total_org_count: 20,
                                      total_pkg_count: 100, success_org_count: 20, failed_org_count: 0,
                                      success_pkg_count: 100, failed_pkg_count: 0, state: :inProgress)
          migration_run_2.update(state: :completed)

          assert_difference "ActionMailer::Base.deliveries.size", 0 do
            mail = ActionMailer::Base.deliveries.last
            assert_equal mail.subject, "[GitHub] Your GitHub Enterprise Server packages migration is complete"
          end
        end
      end
    end

  end
end
