# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

unless GitHub.single_business_environment?
  class BusinessUpdateLicenseUsageJobTest < GitHub::TestCase
    include GitHub::LoggerHelper
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @org = create :organization
      @private_repo_user = create :user
      @private_repo = create(:private_repository, :minimal, owner: @org)
      @private_repo.add_member(@private_repo_user)

      @public_repo_user = create :user
      @public_repo = create(:public_repository, :minimal, owner: @org)
      @public_repo.add_member(@public_repo_user)

      @assigned_user = create :user

      @business = create :business, organizations: [@org]
      create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 2)
      create(:licensing_bundled_license_assignment, user: @assigned_user, business: @business)

      @emu = create :emu, :owner
      @emu_business = @emu.enterprise_managed_business
      @emu_org = create :organization, business: @emu_business, admin: @emu
    end

    def running_cache_key(business: @business)
      "#{BusinessUpdateLicenseUsageJob::CACHE_KEY_PREFIX}:running:#{business.id}"
    end

    def run_again_cache_key(business: @business)
      "#{BusinessUpdateLicenseUsageJob::CACHE_KEY_PREFIX}:run_again:#{business.id}"
    end

    def set_job_running_key
      GitHub.job_coordination_redis.set(running_cache_key, 1, nx: true, ex: 1.minute.to_i)
    end

    def set_run_again_key
      GitHub.job_coordination_redis.set(run_again_cache_key, 1, nx: true, ex: 1.minute.to_i)
    end

    test "does not queue another job if no other job is running" do
      assert_enqueued_jobs 0, only: BusinessUpdateLicenseUsageJob do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      refute GitHub.job_coordination_redis.get(run_again_cache_key)
    end

    test "deletes running key at the end of the job" do
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      refute GitHub.job_coordination_redis.get(running_cache_key)
    end

    test "sets key to queue another job if job is currently running" do
      set_job_running_key
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      assert GitHub.job_coordination_redis.get(run_again_cache_key)
    end

    test "exits early if another job is already running" do
      set_job_running_key

      expected_keys = {
        Body: "license usage update requested",
        "gh.business.id": @business.id,
        "gh.business.slug": @business.slug,
        "gh.license_usage.completed": false,
      }
      assert_logged(**expected_keys) do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
    end

    test "queues another job if run_again is set" do
      set_run_again_key

      expected_keys = {
        Body: "license usage update scheduled",
        "gh.business.id": @business.id,
        "gh.business.slug": @business.slug,
        "gh.license_usage.completed": false,
      }
      assert_logged(**expected_keys) do
        assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob do
          BusinessUpdateLicenseUsageJob.perform_now(@business.id)
        end
      end
    end

    test "clears key when an unexpected error is thrown" do
      ::Business::LicenseUsage.any_instance.stubs(:save!).raises(StandardError)

      error = assert_raises StandardError do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
      refute GitHub.job_coordination_redis.get(running_cache_key)
    end

    test "deletes run_again key when job is run again" do
      set_run_again_key
      assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
      refute GitHub.job_coordination_redis.get(run_again_cache_key)
    end

    test "retries if record is not found" do
      @business.destroy

      BusinessUpdateLicenseUsageJob.any_instance.expects(:retry_job)
      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
        BusinessUpdateLicenseUsageJob.perform_later(@business.id)
      end
    end

    test "does not increment active_job.error if exhausted retries trying to find business" do
      @business.destroy

      logger_output = {
        "exception.type": ActiveRecord::RecordNotFound.name,
        "code.namespace": BusinessUpdateLicenseUsageJob.name,
        "code.method": "perform",
      }

      assert_logged(**logger_output) do
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
          BusinessUpdateLicenseUsageJob.perform_later(@business.id)
        end
      end
      refute_dogstats_increment "active_job.error"
    end

    test "logs and rejects soft deleted businesses" do
      deletable_business = create :business
      perform_enqueued_jobs only: SoftDeleteBusinessJob do
        deletable_business.soft_delete!
      end

      logger_output = {
        "Body": "Attempted to update license usage for soft deleted business",
        "code.namespace": BusinessUpdateLicenseUsageJob.name,
        "code.method": "perform",
      }

      assert_logged(**logger_output) do
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
          BusinessUpdateLicenseUsageJob.perform_later(deletable_business.id)
        end
      end
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: BusinessUpdateLicenseUsageJob
    end

    test "sets generated_at" do
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      refute_nil @business.license_usage.generated_at
    end

    test "creates license_usage if it does not exist" do
      @business.license_usage&.destroy
      assert_nil @business.reload.license_usage
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      refute_nil @business.reload.license_usage
    end

    test "license_usage stores consumed_enterprise_licenses" do
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      assert_equal @business.consumed_enterprise_licenses, @business.license_usage.consumed_enterprise_licenses
    end

    test "license_usage stores consumed_volume_licenses" do
      BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      assert_equal @business.consumed_volume_licenses, @business.license_usage.consumed_volume_licenses
    end

    test "logs completion using GitHub::Logger" do
      expected_keys = {
        "gh.business.id": @business.id,
        "gh.business.slug": @business.slug,
        "gh.license_usage.completed": true,
        "gh.license_usage.consumed_enterprise_licenses": 2,
        "gh.license_usage.consumed_volume_licenses": 1,
        "gh.business.seats": @business.seats
      }
      assert_logged(**expected_keys) do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
    end

    test "does not retry if it succeeds" do
      assert_enqueued_jobs 0, only: BusinessUpdateLicenseUsageJob do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
    end

    test "retries when there is already a license record on primary but not replica" do
      Business::LicenseUsage.build(business_id: @business.id, generated_at: Time.now).save(validate: false)
      assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
    end

    test "raises for other record validation errors" do
      ::Business::LicenseUsage.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)
      error = assert_raises ActiveRecord::RecordInvalid do
        BusinessUpdateLicenseUsageJob.perform_now(@business.id)
      end
    end

    test "retries for some errors" do
      arguments = [@business.id]
      assert_retry_on_error(Faraday::Error, BusinessUpdateLicenseUsageJob, arguments)
      assert_retry_on_error(ActiveRecord::RecordNotFound, BusinessUpdateLicenseUsageJob, arguments)
      assert_retry_on_error(BusinessUpdateLicenseUsageJob::RecordAlreadyExists, BusinessUpdateLicenseUsageJob, arguments)
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions(job: BusinessUpdateLicenseUsageJob, args: [@business.id])
    end

    if TestEnv.test_in_multitenancy_mode?
      test "resolves tenant context with business id" do
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        BusinessUpdateLicenseUsageJob.perform_now(@business.id)

        assert_equal @business, GitHub::CurrentTenant.get
      end

      test "resolves tenant context with business object" do
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        BusinessUpdateLicenseUsageJob.perform_now(@business)

        assert_equal @business, GitHub::CurrentTenant.get
      end
    end
  end
end
