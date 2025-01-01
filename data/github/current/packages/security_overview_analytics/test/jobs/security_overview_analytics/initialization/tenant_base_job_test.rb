# typed: true
# frozen_string_literal: true

require_relative "../../../../../security_products/app/models/security_center/k_v"

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class TenantBaseJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        @org = create(:organization)
        @repos = create_list(:repository, 10, owner: @org)
      end

      setup do
        @initialization = Initialization.for(@org)
      end

      context "when no missing metric initializations exist" do
        test "it does not perform" do
          @initialization.set_all_to_initialized

          assert_no_performed_jobs(only: TenantBaseJobSubclass) do
            TenantBaseJobSubclass.perform_later(organization_id: @org.id)
          end
        end
      end

      context "when one metric of initializations exist" do
        test "it does not perform for the same metric type" do
          @initialization.set_type_to_initialized(type: Initialization::Type::SecretScanningAlert)

          assert_no_performed_jobs(only: TenantBaseJobSubclass) do
            TenantBaseJobSubclass.perform_later(organization_id: @org.id, type: Initialization::Type::SecretScanningAlert.serialize)
          end
        end

        test "it will perform for a different metric that has missing initialization" do
          @initialization.set_type_to_initialized(type: Initialization::Type::SecretScanningAlert)

          assert_enqueued_jobs 1, only: TenantBaseJobSubclass do
            TenantBaseJobSubclass.perform_later(organization_id: @org.id, type: Initialization::Type::CodeScanningAlert.serialize)
          end
        end

        test "it will retry on retriable error with a different metric that has missing initialization" do
          @initialization.set_type_to_initialized(type: Initialization::Type::SecretScanningAlert)

          assert_performed_jobs 2, only: FailureTestJob do
            FailureTestJob.perform_later(organization_id: @org.id, type: Initialization::Type::CodeScanningAlert.serialize)
          end
        end
      end

      context "when missing metric initializations exist" do
        test "it performs" do
          assert_performed_with(job: TenantBaseJobSubclass) do
            TenantBaseJobSubclass.perform_later(organization_id: @org.id)
          end
        end

        test "subsequent job enqueues and performs do not set statuses for missing metric initializations" do
          Initialization.any_instance.expects(:set_all_to_initialized).times(1)

          perform_enqueued_jobs(only: TenantBaseJobSubclass) do
            TenantBaseJobSubclass.perform_later(organization_id: @org.id)
          end
        end

        test "it sets a status for missing metric initializations on job perform" do
          assert_changes(
            -> { @initialization.any_uninitialized? },
            from: true,
            to: false
          ) do
            TenantBaseJobSubclass.perform_now(organization_id: @org.id)
          end
        end

        test "it sets a status only for missing metric type requested on job perform" do
          assert_changes(
            -> { @initialization.initialized?(type: Initialization::Type::SecretScanningAlert) },
            from: false,
            to: true
          ) do
            TenantBaseJobSubclass.perform_now(organization_id: @org.id, type: Initialization::Type::SecretScanningAlert.serialize)
          end
          assert @initialization.any_uninitialized?
        end

        test "it will retry on retriable error" do
          assert_performed_jobs 2, only: FailureTestJob do
            FailureTestJob.perform_later(organization_id: @org.id)
          end
        end
      end
    end

    class FailureTestJob < TenantBaseJob
      sig { override.returns(Initialization) }
      def initialization
        Initialization.for(organization)
      end

      sig do
        override
          .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
          .returns(T.all(T::Enumerable[T.untyped], Object))
      end
      def fetch_batch(*args, offset_id:, **kwargs)
        raise ActiveRecord::RecordNotFound if exception_executions.blank?
        ::Repository.none
      end

      sig { override.params(args: T.untyped, item: T.untyped, type: T.nilable(String), kwargs: T.untyped).void }
      def process_item(*args, item:, type: nil, **kwargs)
        # DO NOTHING
      end

      sig { override.returns(Float) }
      memoize def timeout_sec
        0.0
      end

      sig { returns(Integer) }
      memoize def organization_id
        (arguments[0] || {}).fetch(:organization_id)
      end

      sig { returns(::Organization) }
      memoize def organization
        ::Organization.find(organization_id)
      end
    end

    class TenantBaseJobSubclass < TenantBaseJob
      sig { returns(String) }
      def self.perform_counter_kv_key
        "tenant_base_job_subclass.process_item.counter"
      end

      sig { override.returns(Initialization) }
      def initialization
        Initialization.for(organization)
      end

      sig do
        override
          .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
          .returns(T.all(T::Enumerable[T.untyped], Object))
      end
      def fetch_batch(*args, offset_id:, **kwargs)
        ::Repository
          .where(active: true, organization_id:)
          .where(::Repository.arel_table[:id].gt(offset_id))
          .order(:id)
          .limit(1000)
          .pluck(:id)
      end

      sig { override.params(args: T.untyped, item: T.untyped, type: T.nilable(String), kwargs: T.untyped).void }
      def process_item(*args, item:, type: nil, **kwargs)
        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.increment(self.class.perform_counter_kv_key)
        end
      end

      sig { override.returns(Float) }
      memoize def timeout_sec
        0.0
      end

      sig { returns(Integer) }
      memoize def organization_id
        (arguments[0] || {}).fetch(:organization_id)
      end

      sig { returns(::Organization) }
      memoize def organization
        ::Organization.find(organization_id)
      end
    end
  end
end
