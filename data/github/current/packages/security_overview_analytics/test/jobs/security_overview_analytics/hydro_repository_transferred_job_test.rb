# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryTransferredJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers

    fixtures do
      # Referencing the job class forces it to load
      # This is necessary for job to show up during queue name lookup
      @queue = HydroRepositoryTransferredJob.queue_name
      @schema = "github.repositories.v1.Transferred"

      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

      @org_1_in_scope = create(:organization)
      @org_2_in_scope = create(:organization)
      @org_1_not_in_scope = create(:organization)
      @org_2_not_in_scope = create(:organization)

      @user_1_in_scope = create(:user)
      @user_2_in_scope = create(:user)
      @user_1_not_in_scope = create(:user)
      @user_2_not_in_scope = create(:user)

      @repo = create(:private_repository, owner: @org_1_in_scope)
      @user_repo = create(:private_repository, owner: @user_1_in_scope, force_user_owned: true)

      @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
      @user_soa_repo = create(:security_overview_analytics_repository, repository: @user_repo)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org_1_in_scope.id).returns(true)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org_2_in_scope.id).returns(true)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org_1_not_in_scope.id).returns(false)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org_2_not_in_scope.id).returns(false)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@user_1_in_scope.id).returns(true)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@user_2_in_scope.id).returns(true)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@user_1_not_in_scope.id).returns(false)
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@user_2_not_in_scope.id).returns(false)
    end

    context "when repo lifecycle events are not being handled for the new owner" do
      context "when a row matching the org repo exists in soa_repositories" do
        test "it deletes the row in soa_repositories" do
          assert_changes(
            -> { ::SecurityOverviewAnalytics::Repository.count },
            from: ::SecurityOverviewAnalytics::Repository.count,
            to: ::SecurityOverviewAnalytics::Repository.count - 1
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @org_1_not_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "when a row matching the user repo exists in soa_repositories" do
        test "it deletes the row in soa_repositories" do
          assert_changes(
            -> { ::SecurityOverviewAnalytics::Repository.count },
            from: ::SecurityOverviewAnalytics::Repository.count,
            to: ::SecurityOverviewAnalytics::Repository.count - 1
          ) do
            # This is a theoretical scenario, as in practice users that are in scope
            # can't transfer repos out of scope, as the only two supported scenarios
            # are GHES and EMU users - both are always staying in scope, and can't transfer repos out of scope.
            message = make_message(repo: @user_repo, previous_owner: @user_1_in_scope, new_owner: @org_1_not_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "when a row matching the org repo does not exist in soa_repositories" do
        test "it does nothing" do
          @soa_repo.destroy
          refute(::SecurityOverviewAnalytics::Repository.find_by(repository_id: @repo.id))

          assert_no_changes(-> { ::SecurityOverviewAnalytics::Repository.count }) do
            message = make_message(repo: @repo, previous_owner: @org_1_not_in_scope, new_owner: @org_2_not_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "when a row matching the user repo does not exist in soa_repositories" do
        test "it does nothing" do
          @user_soa_repo.destroy
          refute(::SecurityOverviewAnalytics::Repository.find_by(repository_id: @user_repo.id))

          assert_no_changes(-> { ::SecurityOverviewAnalytics::Repository.count }) do
            message = make_message(repo: @repo, previous_owner: @user_1_not_in_scope, new_owner: @user_2_not_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end
    end

    context "when repo lifecycle events are being handled for the new owner" do
      context "when repo metadata does not exist in soa_repositories" do
        test "it creates a row in soa_repositories" do
          @soa_repo.destroy
          refute(::SecurityOverviewAnalytics::Repository.find_by(repository_id: @repo.id))

          Initialization::Repositories::CodeScanningAlertsJob.expects(:perform_later).once
          Fanout::Initialization::CodeScanningPullRequestAlertsJob.expects(:perform_later).once
          Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).once
          Initialization::Repositories::DependabotAlertsJob.expects(:perform_later).once

          assert_changes(
            -> { ::SecurityOverviewAnalytics::Repository.count },
            from: ::SecurityOverviewAnalytics::Repository.count,
            to: ::SecurityOverviewAnalytics::Repository.count + 1
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_not_in_scope, new_owner: @org_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "it changes the organization_id in soa_repositories" do
        test "from org to org" do
          assert_changes(
            -> { @soa_repo.reload.organization_id },
            from: @org_1_in_scope.id,
            to: @org_2_in_scope.id
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @org_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from org to user" do
          assert_changes(
            -> { @soa_repo.reload.organization_id },
            from: @org_1_in_scope.id,
            to: 0,
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @user_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from user to org" do
          assert_changes(
            -> { @user_soa_repo.reload.organization_id },
            from: 0,
            to: @org_2_in_scope.id,
          ) do
            message = make_message(repo: @user_repo, previous_owner: @user_1_in_scope, new_owner: @org_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "it changes the owner_id in soa_repositories" do
        test "from org to org" do
          assert_changes(
            -> { @soa_repo.reload.owner_id },
            from: @org_1_in_scope.id,
            to: @org_2_in_scope.id,
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @org_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from org to user" do
          assert_changes(
            -> { @soa_repo.reload.owner_id },
            from: @org_1_in_scope.id,
            to: @user_2_in_scope.id,
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @user_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from user to org" do
          assert_changes(
            -> { @user_soa_repo.reload.owner_id },
            from: @user_1_in_scope.id,
            to: @org_2_in_scope.id,
          ) do
            message = make_message(repo: @user_repo, previous_owner: @user_1_in_scope, new_owner: @org_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from user to user" do
          assert_changes(
            -> { @user_soa_repo.reload.owner_id },
            from: @user_1_in_scope.id,
            to: @user_2_in_scope.id,
          ) do
            message = make_message(repo: @user_repo, previous_owner: @user_1_in_scope, new_owner: @user_2_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "it changes the owner_type in soa_repositories" do
        test "from org to user" do
          assert_changes(
            -> { @soa_repo.reload.owner_type },
            from: "ORGANIZATION",
            to: "USER",
          ) do
            message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @user_1_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        test "from user to org" do
          assert_changes(
            -> { @user_soa_repo.reload.owner_type },
            from: "USER",
            to: "ORGANIZATION",
          ) do
            message = make_message(repo: @user_repo, previous_owner: @user_1_in_scope, new_owner: @org_1_in_scope)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "it changes business_id in soa_repositories" do
        # Skipping EMUs since a repo cannot be transferred out of the managed business
        # Skipping GHES since there can only be one business in that environment
        test "from org to org", skip_with_all_emus: true, skip_enterprise: true do
          business_1 = create(:global_business)
          business_2 = create(:business)
          org_1 = create(:business_plus_organization, business: business_1)
          org_2 = create(:business_plus_organization, business: business_2)

          repo = create(:private_repository, owner: org_1)
          soa_repo = create(:security_overview_analytics_repository, repository: repo)
          repo.transfer_ownership_to org_2, actor: repo.owner.admins.first

          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(org_1.id).returns(true)
          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(org_2.id).returns(true)

          assert_changes(
            -> { soa_repo.reload.business_id },
            from: business_1.id,
            to: business_2.id,
          ) do
            message = make_message(repo:, previous_owner: org_1, new_owner: org_2)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        # Skipping EMUs since a repo cannot be transferred out of the managed business
        # Skipping GHES since there can only be one business in that environment
        test "from user to org", skip_with_all_emus: true, skip_enterprise: true do
          user = create(:user)
          org = create(:business_plus_organization)
          business_1 = create(:global_business)
          business_2 = create(:business, organizations: [org])

          repo = create(:private_repository, owner: user)
          soa_repo = create(:security_overview_analytics_repository, repository: repo)
          repo.transfer_ownership_to org, actor: repo.owner.admins.first

          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(user.id).returns(true)
          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(org.id).returns(true)

          assert_changes(
            -> { soa_repo.reload.business_id },
            from: TestEnv.test_with_all_emus? ? business_1.id : nil,
            to: business_2.id,
          ) do
            message = make_message(repo:, previous_owner: user, new_owner: org)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        # Skipping EMUs since a repo cannot be transferred out of the managed business
        # Skipping GHES since there can only be one business in that environment
        test "from org to user", skip_with_all_emus: true, skip_enterprise: true do
          business_1 = create(:global_business)
          business_2 = create(:business)
          user = create(:user)
          org = create(:business_plus_organization, business: business_2)

          repo = create(:private_repository, owner: org)
          soa_repo = create(:security_overview_analytics_repository, repository: repo)
          repo.transfer_ownership_to user, actor: repo.owner.admins.first

          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(user.id).returns(true)
          TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(org.id).returns(true)

          assert_changes(
            -> { soa_repo.reload.business_id },
            from: business_2.id,
            to: TestEnv.test_with_all_emus? ? business_1.id : nil,
          ) do
            message = make_message(repo:, previous_owner: org, new_owner: user)
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      test "it updates updated_at column" do
        assert_changes(
          -> { @soa_repo.reload.updated_at }
        ) do
          message = make_message(repo: @repo, previous_owner: @org_1_in_scope, new_owner: @org_2_in_scope)
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      context "when the repo's name is changed" do
        test "it changes the name in soa_repositories" do
          new_name = SecureRandom.uuid

          assert_changes(
            -> { @soa_repo.reload.name },
            from: @soa_repo.name,
            to: new_name,
          ) do
            message = make_message(
              repo: @repo,
              previous_owner: @org_1_in_scope,
              new_owner: @org_2_in_scope,
              new_repo_name: new_name
            )
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      context "when the repo's visibility is changed" do
        test "it changes the visibility in soa_repositories" do
          assert_changes(
            -> { @soa_repo.reload.visibility },
            from: "private",
            to: "internal",
          ) do
            message = make_message(
              repo: @repo,
              previous_owner: @org_1_in_scope,
              new_owner: @org_2_in_scope,
              new_repo_visibility_hydro: :INTERNAL
            )
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end
    end

    private

    sig do
      params(
        repo: ::Repository,
        previous_owner: User,
        new_owner: User,
        new_repo_name: String,
        new_repo_visibility_hydro: Symbol
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def make_message(repo:, previous_owner:, new_owner:, new_repo_name: T.must(repo.name), new_repo_visibility_hydro: :PRIVATE)
      previous_owner_serialized = Hydro::EntitySerializer.user(previous_owner)
      previous_owner_serialized[:created_at] = Google::Protobuf::Timestamp.new(seconds: previous_owner_serialized[:created_at].to_i)

      new_owner_serialized = Hydro::EntitySerializer.user(new_owner)
      new_owner_serialized[:created_at] = Google::Protobuf::Timestamp.new(seconds: new_owner_serialized[:created_at].to_i)

      msg = T.cast(Hydro::Schemas::Github::Repositories::V1::Transferred.new(
        repository_id: repo.id,
        previous_owner: Hydro::Schemas::Github::V1::Entities::User.new(previous_owner_serialized),
        new_owner: Hydro::Schemas::Github::V1::Entities::User.new(new_owner_serialized),
        previous_name: repo.name,
        new_name: new_repo_name,
        new_visibility: new_repo_visibility_hydro
      ), T.untyped).to_h
      msg[:previous_owner][:created_at] = Time.at(msg.dig(:previous_owner, :created_at, :seconds))
      msg[:new_owner][:created_at] = Time.at(msg.dig(:new_owner, :created_at, :seconds))
      msg
    end
  end
end
