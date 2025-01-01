# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class FanoutSchedulerTest < GitHub::TestCase
    context ".initialize_for" do
      test "enqueues initialization fanout for an organization" do
        org = create(:organization)
        assert_enqueued_with job: Fanout::RepositoryOwnerJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Organization.serialize,
          tenant_id: org.id,
          action: Fanout::Types::Action::Initialize.serialize
        ] do
          FanoutScheduler.initialize_for(org)
        end
      end

      test "enqueues initialization fanout for a user" do
        user = create(:user)
        assert_enqueued_with job: Fanout::RepositoryOwnerJob, args: [
          tenant_scope: Fanout::Types::TenantScope::User.serialize,
          tenant_id: user.id,
          action: Fanout::Types::Action::Initialize.serialize
        ] do
          FanoutScheduler.initialize_for(user)
        end
      end

      test "enqueues initialization fanout for a business" do
        biz = create(:business)
        FanoutScheduler.initialize_for(biz)
        assert_enqueued_with job: Fanout::BusinessJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          tenant_id: biz.id,
          owner_type: Fanout::Types::Owner::Organization.serialize,
          action: Fanout::Types::Action::Initialize.serialize
        ]
        assert_enqueued_with job: Fanout::BusinessJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          tenant_id: biz.id,
          owner_type: Fanout::Types::Owner::User.serialize,
          action: Fanout::Types::Action::Initialize.serialize
        ]
      end


      test "raises for unsupported scope" do
        assert_raises do
          FanoutScheduler.initialize_for(T.unsafe(1))
        end
      end
    end

    context ".reconcile_for" do
      test "enqueues reconciliation fanout for an organization" do
        org = create(:organization)
        assert_enqueued_with job: Fanout::RepositoryOwnerJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Organization.serialize,
          tenant_id: org.id,
          action: Fanout::Types::Action::Reconcile.serialize
        ] do
          FanoutScheduler.reconcile_for(org)
        end
      end

      test "enqueues reconciliation fanout for a user" do
        user = create(:user)
        assert_enqueued_with job: Fanout::RepositoryOwnerJob, args: [
          tenant_scope: Fanout::Types::TenantScope::User.serialize,
          tenant_id: user.id,
          action: Fanout::Types::Action::Reconcile.serialize
        ] do
          FanoutScheduler.reconcile_for(user)
        end
      end

      test "enqueues reconciliation fanout for a business" do
        biz = create(:business)
        FanoutScheduler.reconcile_for(biz)
        assert_enqueued_with job: Fanout::BusinessJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          tenant_id: biz.id,
          owner_type: Fanout::Types::Owner::Organization.serialize,
          action: Fanout::Types::Action::Reconcile.serialize
        ]
        assert_enqueued_with job: Fanout::BusinessJob, args: [
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          tenant_id: biz.id,
          owner_type: Fanout::Types::Owner::User.serialize,
          action: Fanout::Types::Action::Reconcile.serialize
        ]
      end


      test "raises for unsupported scope" do
        assert_raises do
          FanoutScheduler.reconcile_for(T.unsafe(1))
        end
      end
    end
  end
end
