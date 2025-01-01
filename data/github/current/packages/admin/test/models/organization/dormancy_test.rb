# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDormancyTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @long_ago = (Time.now - (GitHub.dormancy_threshold + 1.month)).freeze
    @recently = (Time.now - (GitHub.dormancy_threshold - 15.days)).freeze

    Timecop.freeze(@long_ago) do
      @admin_user = create :user
      @org = create :free_org, admin: @admin_user
      @repo = create(:repository, :minimal, owner: @org)
      @repo.update_column :pushed_at, nil
    end
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
    T.unsafe(GitHub).reset_stratocaster
  end

  def is_active_time?(time)
    time.present? && time > GitHub.dormancy_threshold.ago
  end

  context "#dormant?" do
    if GitHub.enterprise?
      test "is always false" do
        refute @org.dormant?
      end
    else
      test "is true" do
        assert @org.dormant?
      end
    end
  end

  context "exempt_from_dormancy?" do
    if GitHub.enterprise?
      test "is always true" do
        assert @org.exempt_from_dormancy?
      end
    else
      test "is false" do
        refute @org.exempt_from_dormancy?
      end

      test "is false if on a paid plan" do
        @org.update plan: "Bronze"
        refute @org.dormant?
      end

      test "is false if on paid plan and disabled" do
        @org.update plan: "Bronze", disabled: true
        refute @org.exempt_from_dormancy?
      end

      test "is true if has active repo" do
        repo = create(:repository, :minimal, owner: @org)
        repo.update_column :pushed_at, Time.now - 15.minutes
        assert @org.exempt_from_dormancy?
      end

      test "true when has collaboration" do
        Timecop.freeze(@long_ago + 5.days) do
          newbie = create(:user)
          @org.add_member(newbie)

          repo = create(:repository, :minimal, owner: @org)
          repo.update_column :pushed_at, Time.now - 15.minutes
        end
        assert @org.exempt_from_dormancy?
      end

      test "is true when strict and org admin is recently active" do
        @admin_user.star(@repo)
        assert @org.exempt_from_dormancy?(strict: true)
      end

      test "is true if strict and has active repo" do
        repo = create(:repository, :minimal, owner: @org)
        repo.update_column :pushed_at, Time.now - 15.minutes
        assert @org.exempt_from_dormancy?(strict: true)
      end

      test "is false when `pushed_at` is nil for repo" do
        repo = create(:repository, :minimal, owner: @org)
        repo.update!(pushed_at: nil)
        assert_nil repo.pushed_at
        refute @org.exempt_from_dormancy?
      end

      test "false when strict and has collaboration" do
        Timecop.freeze(@long_ago + 5.days) do
          newbie = create(:user)
          @org.add_member(newbie)

          repo = create(:repository, :minimal, owner: @org)
          repo.update_column :pushed_at, Time.now - 15.minutes
        end
        refute @org.exempt_from_dormancy?(strict: true)
      end

      test "true if owner account is active" do
        @admin_user.star(@repo)
        assert @org.exempt_from_dormancy?(strict: true)
      end

      test "true if the org has recent admin activity" do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :minimal, owner: @org }
        assert @org.exempt_from_dormancy?(strict: true)
      end

      unless GitHub.single_business_environment?
        test "doesn't error when strict and org has no admins" do
          @org.business = create(:business_saml_provider).business
          GitHub.flipper[:enterprise_idp_provisioning].enable(@org.business)
          @org.remove_member!(@admin_user, allow_last_admin_removal: true)
          assert @org.exempt_from_dormancy?(strict: true)
        end
      end
    end
  end

  context "#recently_active?" do
    test "is false" do
      refute @org.recently_active?
    end

    test "is true if org was created recently" do
      @org.update created_at: @recently
      assert @org.recently_active?
    end

    if GitHub.billing_enabled?
      test "is true if org has a recent transaction" do
        create :billing_transaction, user: @org
        assert @org.recently_active?
      end

      test "is false if org only has old transactions" do
        Timecop.freeze(@long_ago) do
          create :billing_transaction, user: @org
        end
        refute @org.recently_active?
      end
    end

    test "is true if org has a recent feed event" do
      only = [ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { create :issue, :with_instrumentation, :wait_for_orchestration, repository: @repo }
      assert @org.recently_active?
    end

    test "is false if org's newest feed event is too old" do
      Timecop.freeze(@long_ago) do
        create :issue, repository: @repo
      end
      refute @org.recently_active?
    end

    test "is true if the org has a recent audit log entry" do
      with_es_refresh do
        log action: "org.rename", org_id: @org.id, org: @org.name
      end

      assert @org.recently_active?
    end

    test "is false if the org has only old audit log entries" do
      with_es_refresh do
        Timecop.freeze(@long_ago) do
          log action: "org.rename", org_id: @org.id, org: @org.name
        end
      end

      refute @org.recently_active?
    end

    test "is false if the org only has member-specific audit log entries" do
      with_es_refresh do
        log action: "user.login", org_id: [@org.id]
      end

      refute @org.recently_active?
    end

    test "is false if the org has only forbidden audit log entries" do
      with_es_refresh do
        log action: "staff.repo_lock", org_id: @org.id, org: @org.name
      end

      refute @org.recently_active?
    end
  end
  context "#dormancy_status" do
    unless GitHub.enterprise?
      test "dormant when dormant" do
        assert @org.dormancy_status[:dormant]
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "active when org was created recently" do
        @org.update created_at: @recently
        refute @org.dormancy_status[:dormant]
        assert is_active_time?(@org.dormancy_status[:created_at])
        assert_includes @org.dormancy_status[:active_keys], :created_at
      end

      test "active when org is recently paid" do
        create :billing_transaction, user: @org
        refute @org.dormancy_status[:dormant]
        assert is_active_time?(@org.dormancy_status[:last_transaction])
        assert_includes @org.dormancy_status[:active_keys], :last_transaction
      end

      test "dormant if org only has old transactions" do
        Timecop.freeze(@long_ago) do
          create :billing_transaction, user: @org
        end
        assert @org.dormancy_status[:dormant]
        refute is_active_time?(@org.dormancy_status[:last_transaction])
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "active if has active repo" do
        repo = create(:repository, :minimal, owner: @org)
        repo.update_column :pushed_at, Time.now - 15.minutes
        refute @org.dormancy_status[:dormant]
        assert_equal 2, @org.dormancy_status[:ignored][:repo_owner_count]
        assert @org.dormancy_status[:active_repo_owner]
        assert_includes @org.dormancy_status[:active_keys], :active_repo_owner
      end

      test "active if has an old repo with recent push" do
        Timecop.freeze(@long_ago) do
          @repo = create(:repository, :minimal, owner: @org)
          @repo.update_column :pushed_at, Time.now - 15.minutes
        end

        @repo.update_column :pushed_at, Time.now - 15.minutes

        refute @org.dormancy_status[:dormant]
        assert_equal 2, @org.dormancy_status[:ignored][:repo_owner_count]
        assert @org.dormancy_status[:active_repo_owner]
      end

      test "dormant if has an old repo " do
        Timecop.freeze(@long_ago) do
          @repo = create(:repository, :minimal, owner: @org)
          @repo.update_column :pushed_at, Time.now - 15.minutes
        end

        assert @org.dormancy_status[:dormant]
        assert_equal 2, @org.dormancy_status[:ignored][:repo_owner_count]
        refute @org.dormancy_status[:active_repo_owner]
      end

      test "dormant when has collaboration" do
        Timecop.freeze(@long_ago + 5.days) do
          newbie = create(:user)
          @org.add_member(newbie)

          repo = create(:repository, :minimal, owner: @org)
          repo.update_column :pushed_at, Time.now - 15.minutes
        end
        assert @org.dormancy_status[:dormant]
        assert @org.dormancy_status[:ignored][:org_collaboration]
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "dormant if many members" do
        Timecop.freeze(@long_ago + 5.days) do
          newbie = create(:user)
          @org.add_member(newbie)
        end

        assert @org.dormancy_status[:dormant]
        assert @org.dormancy_status[:ignored][:org_size] > 1
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "active if has dashboard events" do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :issue, :with_instrumentation, :wait_for_orchestration, repository: @repo }
        refute @org.dormancy_status[:dormant]
        assert is_active_time?(@org.dormancy_status[:last_event])
        assert_includes @org.dormancy_status[:active_keys], :last_event
        assert_includes @org.dormancy_status[:active_keys], :last_admin_event
      end

      test "dormant if has old dashboard events" do
        Timecop.freeze(@long_ago) do
          create :issue, repository: @repo
        end
        assert @org.dormancy_status[:dormant]
        refute is_active_time?(@org.dormancy_status[:last_event])
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "active if has audit log events" do
        with_es_refresh do
          log action: "org.rename", org_id: @org.id, org: @org.name
        end
        refute @org.dormancy_status[:dormant]
        assert is_active_time?(@org.dormancy_status[:last_log])
        assert_includes @org.dormancy_status[:active_keys], :last_log
      end

      test "active if owner account is active" do
        @admin_user.star(@repo)
        refute @org.dormancy_status[:dormant]
        assert @org.dormancy_status[:active_admin]
        assert_includes @org.dormancy_status[:active_keys], :active_admin
      end

      test "is active if the org has last admin activity" do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :full_creation, owner: @org }

        refute @org.dormancy_status[:dormant]
        assert is_active_time?(@org.dormancy_status[:last_admin_event])
        assert_includes @org.dormancy_status[:active_keys], :last_admin_event
        assert_includes @org.dormancy_status[:active_keys], :last_event
      end

      test "is dormant if the org only has member-specific audit log entries" do
        with_es_refresh do
          log action: "user.login", org_id: [@org.id]
        end

        assert @org.dormancy_status[:dormant]
        refute is_active_time?(@org.dormancy_status[:last_log])
        assert_equal [], @org.dormancy_status[:active_keys]
      end

      test "is dormant if the org has only forbidden audit log entries" do
        with_es_refresh do
          log action: "staff.repo_lock", org_id: @org.id, org: @org.name
        end
        assert @org.dormancy_status[:dormant]
        refute is_active_time?(@org.dormancy_status[:last_log])
        assert_equal [], @org.dormancy_status[:active_keys]
      end
    end
  end
end
