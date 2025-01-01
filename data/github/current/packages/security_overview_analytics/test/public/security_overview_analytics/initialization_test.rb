# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class InitializationTest < GitHub::TestCase
    fixtures do
      @biz = create(:business)
      @org = create(:organization, business: @biz)
      @org_business_plus = create(:business_plus_organization)
      @tenants = [@biz, @org, @org_business_plus]
    end

    context ".for" do
      context "when scope is a business" do
        test "it returns a Initialization object" do
          assert_instance_of(Initialization, Initialization.for(@biz))
        end
      end

      context "when scope is an organization" do
        test "it returns a Initialization object" do
          assert_instance_of(Initialization, Initialization.for(@org))
        end
      end

      context "when scope is a user" do
        test "it returns a Initialization object for users" do
          user = create(:user)
          assert_instance_of(Initialization, Initialization.for(user))
        end
      end

      context "when scope is an unsupported type" do
        test "it raises an error" do
          assert_raises do
            Initialization.for(T.unsafe(1))
          end
        end
      end
    end

    context "#enqueue" do
      test "it enqueues a job to initialize the metrics for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          job_class =
            case tenant
            when ::Business
              Initialization::BusinessJob
            when ::Organization
              Initialization::OrganizationJob
            end

          assert_enqueued_with(job: job_class) do
            initialization.enqueue
          end
        end
      end
    end

    context "#initialized?" do
      test "it returns whether or not a metric has been initialized for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          kv_key = "#{initialization.strategy.initialization_key_prefix}.#{Initialization::Type::FeatureEnablement.serialize}"

          assert_changes(
            -> { initialization.initialized?(type: Initialization::Type::FeatureEnablement) },
            from: false,
            to: true
          ) do
            SecurityCenter::KV.store.set(kv_key, "true")
          end
        end
      end
    end

    context "#all_initialized?" do
      context "when all metrics are initialized for the tenant" do
        test "it returns true" do
          @tenants.each_with_index do |tenant|
            initialization = new_initialization(tenant)
            initialization.delete_all_initializations

            assert_changes(
              -> { initialization.all_initialized? },
              from: false,
              to: true
            ) do
              initialization.set_all_to_initialized
            end
          end
        end
      end

      context "when all metrics are not initialized for the tenant" do
        test "it returns false" do
          @tenants.each_with_index do |tenant|
            initialization = new_initialization(tenant)
            refute(initialization.all_initialized?)
          end
        end
      end

      test "runs feature_enabled? check" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          initialization.delete_all_initializations

          Initialization.any_instance.expects(:feature_enabled?).returns(false).times(initialization.strategy.initialization_types.size)
          initialization.set_all_to_initialized
        end
      end
    end

    context "#any_uninitialized?" do
      test "it returns whether or not any metric is uninitialized for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          assert initialization.any_uninitialized?
        end
      end

      test "runs feature_enabled? check" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)

          Initialization.any_instance.expects(:feature_enabled?).returns(false).times(initialization.strategy.initialization_types.size)
          # No types in KV == not initialized
          assert initialization.any_uninitialized?
        end
      end
    end

    context "#any_initialized?" do
      test "it returns whether or not any metric has been initialized for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)

          assert_changes(
            -> { initialization.any_initialized? },
            from: false,
            to: true
          ) do
            initialization.set_all_to_initialized
          end
        end
      end

      test "runs feature_enabled? check" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)

          Initialization.any_instance.expects(:feature_enabled?).returns(false).times(initialization.strategy.initialization_types.size)
          refute initialization.any_initialized?
        end
      end
    end

    context "#set_all_to_initialized" do
      test "it sets all missing metric to initialized for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)

          assert_changes(
            -> { initialization.any_uninitialized? },
            from: true,
            to: false
          ) do
            initialization.set_all_to_initialized
          end
        end
      end
    end

    context "#delete_all_initializations" do
      test "it deletes all initialization statuses for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          kv_key = "#{initialization.strategy.initialization_key_prefix}.#{Initialization::Type::FeatureEnablement.serialize}"

          SecurityCenter::KV.store.set(kv_key, "true")

          assert_changes(
            -> { SecurityCenter::KV.store.get(kv_key).value! },
            from: "true",
            to: nil
          ) do
            initialization.delete_all_initializations
          end
        end
      end
    end

    context "#delete_initialization" do
      test "it deletes the initialization status for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)
          kv_key = "#{initialization.strategy.initialization_key_prefix}.#{Initialization::Type::FeatureEnablement.serialize}"

          SecurityCenter::KV.store.set(kv_key, "true")

          assert_changes(
            -> {  SecurityCenter::KV.store.get(kv_key).value! },
            from: "true",
            to: nil
          ) do
            initialization.delete_initialization(type: Initialization::Type::FeatureEnablement)
          end
        end
      end
    end

    context "set_type_to_initialized" do
      test "sets a type to initialized for the tenant" do
        @tenants.each_with_index do |tenant|
          initialization = new_initialization(tenant)

          assert_changes(
            -> { initialization.initialized?(type: Initialization::Type::SecretScanningAlert) },
            from: false,
            to: true
          ) do
            initialization.set_type_to_initialized(type: Initialization::Type::SecretScanningAlert)
          end
        end
      end

      test "runs feature_enabled? check" do
        @tenants.each_with_index do |tenant|
          Initialization.any_instance.expects(:feature_enabled?).returns(false).once
          initialization = new_initialization(tenant)

          assert_no_changes(
            -> { initialization.initialized?(type: Initialization::Type::SecretScanningAlert) }
          ) do
            initialization.set_type_to_initialized(type: Initialization::Type::SecretScanningAlert)
          end
        end
      end
    end

    sig { params(tenant: T.any(::Organization, ::Business)).returns(Initialization) }
    def new_initialization(tenant)
      Initialization.for(tenant)
    end
  end
end
