# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class OrganizationEnablementJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @actor = create(:user)
      @user_session = create(:user_session, user: @actor)
      @org = create(:organization).tap do |o|
        o.add_admin(@actor)
        [
          (@public_repo = create(:public_repository, owner: o)),
          (@private_repo = create(:private_repository, owner: o)),
          (@archived_repo = create(:archived_repository, owner: o)),
          (@deleted_repo = create(:deleted_repository, owner: o)),
        ].each do |repo|
          create(:repository_security_center_config, repository: repo)
          RepositorySecurityCenterStatus.all_feature_types.each do |feature_type|
            create(:repository_security_center_status, feature_type, :not_enrolled, repository: repo)
          end
        end
      end
    end

    context "#perform" do
      context "when no organization is found" do
        test "it does not perform any update" do
          perform_job(organization_id: -1)
          assert_no_enqueued_jobs only: RepositoryEnablementJob
        end
      end

      context "when no actor is found" do
        test "it does not perform any update" do
          perform_job(actor_id: -1)
          assert_no_enqueued_jobs only: RepositoryEnablementJob
        end
      end

      context "when no update_type is provided" do
        test "it does not perform any update" do
          perform_job(update_types: [])
          assert_no_enqueued_jobs only: RepositoryEnablementJob
        end
      end

      context "when a single update type is provided" do
        test "passes update type to repository jobs" do
          perform_job
          expected_repos = @org.repositories.active # non-deleted
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end
      end

      context "when multiple update types are provided" do
        test "passes all update types to repository jobs" do
          perform_job(update_types: [:first_action, :second_action])
          expected_repos = @org.repositories.active # non-deleted
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:first_action, :second_action],
              update_options: {},
            }]
          end
        end
      end

      context "when repositories scope is an array of ids" do
        test "queues repository job for each provided repo" do
          perform_job(repositories_scope: [@public_repo.id, @private_repo.id, @deleted_repo.id])

          expected_repos = [@public_repo, @private_repo]
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end
      end

      context "when repositories scope is a filter string" do
        test "queues repository job for each active repository" do
          perform_job(repositories_scope: "")

          expected_repos = [@public_repo, @private_repo, @archived_repo]
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end

        test "queues repository job for each repository matching `archived:true`" do
          perform_job(repositories_scope: "archived:true")

          expected_repos = [@archived_repo]
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end
      end

      context "executes expected number of queries" do
        test "for organization owner" do
          # fanout overhead: 4-5
          # each enqueued repo: 4
          assert_max_query_count(17, ignore_feature_flags: true) do
            perform_job(repositories_scope: "code-scanning-alerts:not-enabled archived:true,false")
          end

          expected_repos = [@public_repo, @private_repo, @archived_repo]
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: @actor.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end

        test "for organization member" do
          member = create(:user).tap do |u|
            @org.add_member(u)
            @private_repo.add_member(u, action: :admin)
          end

          # fanout overhead: 4-5
          # each enqueued repo: 4
          assert_max_query_count(17, ignore_feature_flags: true) do
            perform_job(actor_id: member.id, repositories_scope: "code-scanning-alerts:not-enabled archived:true,false")
          end

          expected_repos = [@public_repo, @private_repo, @archived_repo]
          assert_enqueued_jobs expected_repos.count, only: RepositoryEnablementJob
          expected_repos.each do |repo|
            assert_enqueued_with job: RepositoryEnablementJob, args: [{
              repository_id: repo.id,
              actor_id: member.id,
              update_types: [:job_test_action],
              update_options: {},
            }]
          end
        end
      end
    end

    context "retry" do
      test "basic retry conditions" do
        assert_retry_conditions(job: OrganizationEnablementJob, args: [{
          organization_id: @org.id,
          update_types: [:advanced_security_enable_all],
          actor_id: @actor.id,
          repositories_scope: "is:private",
          user_session_id: @user_session.id,
        }])
      end
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        org = create(:organization).tap do |o|
          10.times do
            create(:private_repository, owner: o).tap do |r|
              create(:repository_security_center_config, repository: r)
            end
          end
        end

        OrganizationEnablementJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: OrganizationEnablementJob do
            perform_enqueued_jobs(only: OrganizationEnablementJob) do
              OrganizationEnablementJob.perform_later(
                organization_id: org.id,
                actor_id: @actor.id,
                update_types: [:job_test_action],
                repositories_scope: "is:private",
                user_session_id: @user_session.id,
              )
            end
          end
        end
      end
    end

    context "hash lock" do
      test "disallows concurrent jobs for same organization" do
        assert_enqueued_jobs 1, only: OrganizationEnablementJob do
          OrganizationEnablementJob.perform_later(organization_id: @org.id, actor_id: @actor.id, user_session_id: @user_session.id, update_types: [:advanced_security_enable_all])
          OrganizationEnablementJob.perform_later(organization_id: @org.id, actor_id: @actor.id, user_session_id: @user_session.id, update_types: [:secret_scanning_enable_all])
          OrganizationEnablementJob.perform_later(organization_id: @org.id, actor_id: @actor.id, user_session_id: @user_session.id, update_types: [:auto_codeql_disable_all])
        end
      end
    end

    private

    def perform_job(actor_id: @actor.id, organization_id: @org.id, repositories_scope: "", update_types: [:job_test_action], user_session_id: @user_session.id)
      OrganizationEnablementJob.perform_now(
        actor_id:,
        organization_id:,
        repositories_scope:,
        update_types:,
        user_session_id:,
      )
    end
  end
end
