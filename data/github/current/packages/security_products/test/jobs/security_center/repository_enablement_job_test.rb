# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_products_enablement/k_v"

module SecurityCenter
  class RepositoryEnablementJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroTestHelpers
    include JobTestHelper

    fixtures do
      @actor = create(:user)
      @user_session = create(:user_session, user: @actor)
      @org = create(:organization).tap do |o|
        o.add_admin(@actor)
        [
          (@repo = create(:private_repository, owner: o)),
          (@public_repo = create(:repository, owner: o)),
        ].each do |repo|
          create(:repository_security_center_config, repository: repo)
        end
      end
    end

    setup do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(false)

      GitHub.flipper[:secret_scanning_owner_service_flags_on_org_enablement].enable
      SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:enabled?).returns(true)
    end

    context "#perform" do
      context "when no repository is found" do
        test "it does not perform any update" do
          SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).never
          RepositoryEnablementJob.perform_now(repository_id: -1, actor_id: @actor.id, update_types: [:job_test_action])
        end
      end

      context "when no actor is found" do
        test "it does not perform any update" do
          SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).never
          RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: -1, update_types: [:job_test_action])
        end
      end

      context "when no update_type is provided" do
        test "it does not perform any update" do
          SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).never
          RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id, update_types: [])
        end
      end

      context "when update type is unknown" do
        test "does not invoke enable or disable for any service" do
          SecurityProduct::Service.any_instance.expects(:on_enable).never
          SecurityProduct::Service.any_instance.expects(:on_disable).never

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:unknown_enable_all])
          end
        end
      end

      context "actor permissions" do
        context "when the actor can manage the repository's security settings" do
          test "it performs updates" do
            org_admin = create(:user).tap { |u| @org.add_admin(u) }
            security_manager = create(:user).tap { |u| @org.add_member(u) }
            security_team = create(:security_manager_team, organization: @org).tap { |team| team.add_member(security_manager) }
            repo_admin = create(:user).tap do |u|
              @org.add_member(u)
              @repo.add_member(u, action: :admin)
            end
            actors = [org_admin, security_manager, repo_admin]

            SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).times(actors.size)
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

            actors.each do |actor|
              perform_enqueued_jobs only: RepositoryEnablementJob do
                RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: actor.id, update_types: [:dependency_graph_enable_all])
              end
            end
          end
        end

        context "when the actor cannot manage the repository's security settings" do
          test "it does not perform any update" do
            anon = create(:user)
            org_member = create(:user).tap { |u| @org.add_member(u) }
            repo_member = create(:user).tap do |u|
              @org.add_member(u)
              @repo.add_member(u)
            end

            SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).never

            [anon, org_member, repo_member].each do |actor|
              perform_enqueued_jobs only: RepositoryEnablementJob do
                RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: actor.id, update_types: [:dependency_graph_enable_all])
              end
            end
          end
        end
      end

      context "when multiple update types are provided" do
        test "invokes all services" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::AdvancedSecurity.any_instance.expects(:enabled?).at_least_once.returns(true)

          CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

          CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          SecurityProduct::TokenScanning.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id, update_types: [
              :auto_codeql_enable_all,
              :secret_scanning_enable_all,
            ])
          end
        end
      end

      context "when no update is applied" do
        test "records noop telemetry" do
          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id, update_types: [
              :job_test_action_1,
              :job_test_action_2,
            ])
          end

          assert_dogstats_increment("security_center.enablement.noop.count", tags: [
            "update_type:job_test_action_1",
            "update_type:job_test_action_2"
          ])
        end
      end

      context "blocked settings" do
        test "manages block counter for a single repository" do
          assert_equal 0, block_counter

          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:job_test_action])
          assert_equal 1, block_counter

          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_equal 0, block_counter
        end

        test "manages block counter for multiple repositories" do
          assert_equal 0, block_counter

          5.times do |i|
            repo = create(:repository, owner: @org)
            RepositoryEnablementJob.perform_later(repository_id: repo.id, actor_id: @actor.id, update_types: [:job_test_action])
            assert_equal i + 1, block_counter
          end

          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_equal 0, block_counter
        end

        test "manages block counter for organization fanout" do
          5.times do
            repo = create(:repository, owner: @org)
            create(:repository_security_center_config, repository: repo)
          end

          assert_equal 0, block_counter

          OrganizationEnablementJob.perform_later(organization_id: @org.id, actor_id: @actor.id, update_types: [:job_test_action], repositories_scope: "", user_session_id: @user_session.id)
          assert_equal 0, block_counter

          perform_enqueued_jobs only: OrganizationEnablementJob
          assert_enqueued_jobs @org.repositories.count, only: RepositoryEnablementJob
          assert_equal @org.repositories.count, block_counter

          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_equal 0, block_counter
        end

        test "maintains counter on retry" do
          assert_equal 0, block_counter

          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:job_test_action])
          assert_equal 1, block_counter

          RepositoryEnablementJob.any_instance.expects(:perform)
            .raises(RepositoryEnablementJob::ToggleServicesError, "boom")

          assert_enqueued_jobs(1, only: RepositoryEnablementJob) do
            perform_enqueued_jobs only: RepositoryEnablementJob
          end
          assert_equal 1, block_counter
        end

        test "decrements counter on terminal error" do
          assert_equal 0, block_counter

          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:job_test_action])
          assert_equal 1, block_counter

          RepositoryEnablementJob.any_instance.expects(:perform)
            .raises(RuntimeError, "boom")

          assert_raises do
            perform_enqueued_jobs only: RepositoryEnablementJob
          end
          assert_equal 0, block_counter
        end

        test "decrements counter on failed permission check" do
          org_member = create(:user).tap { |u| @org.add_member(u) }
          assert_equal 0, block_counter

          SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).never

          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: org_member.id, update_types: [:job_test_action])
          assert_equal 1, block_counter

          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_equal 0, block_counter
        end
      end

      context "when update type is private_vulnerability_reporting_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::PrivateVulnerabilityReporting.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:private_vulnerability_reporting_enable_all])
          end
        end
      end

      context "when update type is private_vulnerability_reporting_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::PrivateVulnerabilityReporting.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:private_vulnerability_reporting_disable_all])
          end
        end
      end

      context "when update type is dependency_graph_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::DependencyGraph.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:dependency_graph_enable_all])
          end
        end
      end

      context "when update type is dependency_graph_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::DependencyGraph.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:dependency_graph_disable_all])
          end
        end
      end

      context "when update type is security_alerts_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::VulnerabilityAlerts.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:security_alerts_enable_all])
          end
        end
      end

      context "when update type is security_alerts_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::VulnerabilityAlerts.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:security_alerts_disable_all])
          end
        end
      end

      context "when update type is vulnerability_updates_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::VulnerabilityUpdates.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:vulnerability_updates_enable_all])
          end
        end
      end

      context "when update type is vulnerability_updates_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::VulnerabilityUpdates.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:vulnerability_updates_disable_all])
          end
        end
      end

      context "when update type is advanced_security_enable_all" do
        test "invokes service on_enable" do
          Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(false)

          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::AdvancedSecurity.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:advanced_security_enable_all])
          end
        end

        context "when in GHES", enterprise_only: true do
          test "invokes service for public repository" do
            Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(false)

            @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
            SecurityProduct::AdvancedSecurity.any_instance.expects(:on_enable).once
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @public_repo.id, actor_id: @actor.id,
                update_types: [:advanced_security_enable_all])
            end
          end
        end

        context "when not in GHES", skip_enterprise: true do
          test "does not invoke service for public repository" do
            SecurityProduct::AdvancedSecurity.any_instance.expects(:on_enable).never

            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @public_repo.id, actor_id: @actor.id,
                update_types: [:advanced_security_enable_all])
            end
          end
        end
      end

      context "when update type is advanced_security_disable_all" do
        test "invokes service on_disable" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::AdvancedSecurity.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:advanced_security_disable_all])
          end
        end

        context "when in GHES", enterprise_only: true do
          test "invokes service for public repositories" do
            SecurityProduct::AdvancedSecurity.any_instance.expects(:on_disable).once
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @public_repo.id, actor_id: @actor.id,
                update_types: [:advanced_security_disable_all])
            end
          end
        end

        context "when not in GHES", skip_enterprise: true do
          test "does not invoke service for public repositories" do
            SecurityProduct::AdvancedSecurity.any_instance.expects(:on_disable).never

            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @public_repo.id, actor_id: @actor.id,
                update_types: [:advanced_security_disable_all])
            end
          end
        end
      end

      context "when update type is auto_codeql_enable_all" do
        test "invokes service enable" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          CodeScanning::Status.stubs(:validate_prerequisites)

          make_trusted_oauth_apps_owner

          VCR.use_cassette(
            "code-scanning/managed-analyses-enable",
            persist_with: :turboscan,
            allow_unused_http_interactions: false,
          ) do
            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
                update_types: [:auto_codeql_enable_all]
              )
            end
          end
        end

        test "invokes service enable with provided query suite" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          CodeScanning::Status.expects(:validate_prerequisites).at_least_once.returns(nil)

          make_trusted_oauth_apps_owner

          [
            ["default", "code-scanning/managed-analyses-enable"],
            ["extended", "code-scanning/managed-analyses-enable-query-suite-extended"],
          ].each do |query_suite, cassette|
            VCR.use_cassette(
              cassette,
              persist_with: :turboscan,
              allow_unused_http_interactions: false,
              match_requests_on: [:method, :uri, -> (actual, expected) do
                actual_body = JSON.parse(actual.body)
                expected_body = JSON.parse(expected.body)
                next false unless (actual_body.keys - expected_body.keys).empty?

                # Passing expected query suite to the onboard request
                actual_body["querySuite"] == expected_body["querySuite"]
              end],
            ) do
              perform_enqueued_jobs only: RepositoryEnablementJob do
                RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
                  update_types: [:auto_codeql_enable_all],
                  update_options: { auto_codeql_query_suite: query_suite },
                )
              end
            end
          end
        end

        test "invokes service enable with recommended suite when no query suite is provided" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          CodeScanning::Status.expects(:validate_prerequisites).at_least_once.returns(nil)

          make_trusted_oauth_apps_owner

          [
            [false, "code-scanning/managed-analyses-enable"],
            [true, "code-scanning/managed-analyses-enable-query-suite-extended"],
          ].each do |recommend_extended_query_suite, cassette|
            Organization.any_instance.stubs(:code_scanning_recommend_extended_query_suite?).returns(recommend_extended_query_suite)

            VCR.use_cassette(
              cassette,
              persist_with: :turboscan,
              allow_unused_http_interactions: false,
              match_requests_on: [:method, :uri, -> (actual, expected) do
                actual_body = JSON.parse(actual.body)
                expected_body = JSON.parse(expected.body)
                next false unless (actual_body.keys - expected_body.keys).empty?

                # Passing expected query suite to the enable request
                actual_body["querySuite"] == expected_body["querySuite"]
              end],
            ) do
              perform_enqueued_jobs only: RepositoryEnablementJob do
                RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
                  update_types: [:auto_codeql_enable_all]
                )
              end
            end
          end
        end

        test "invokes service update if service is already enabled" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          CodeScanning::Status.expects(:validate_prerequisites).returns(nil)

          CodeScanning::AutoCodeql.any_instance.expects(:disabled?).returns(false)

          VCR.use_cassette(
            "code-scanning/managed-analyses-update-querysuite",
            persist_with: :turboscan,
            allow_unused_http_interactions: false,
            match_requests_on: [:method, :uri, -> (actual, expected) do
              actual_body = JSON.parse(actual.body)
              expected_body = JSON.parse(expected.body)
              next false unless (actual_body.keys - expected_body.keys).empty?

              # Passing expected query suite to the update request
              actual_body["querySuite"] == expected_body["querySuite"]
            end],
          ) do
            perform_enqueued_jobs only: RepositoryEnablementJob do
              RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
                update_types: [:auto_codeql_enable_all],
                update_options: { auto_codeql_query_suite: "extended" },
              )
            end
          end
        end

        test "retries batch on circuit breaker error" do
          # eligibility check always succeeds
          CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).twice
            .returns(SecurityProduct::Result.new(true))

          # errors first time, succeeds second time
          CodeScanning::AutoCodeql.any_instance.expects(:on_enable).twice
            .returns(SecurityProduct::Result.new(
              SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {}),
              CodeScanning::AutoCodeqlError.new("boom", repo_id: @repo.id, twirp_error: nil)
            ))
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {})))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:auto_codeql_enable_all])
          end
        end

        test "does not retry on turboscan error" do
          # eligibility check succeeds
          CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once
            .returns(SecurityProduct::Result.new(true))

          # enablement fails
          CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(
              SecurityProduct::ToggledServiceCollection.create(:auto_codeql, {}),
              CodeScanning::AutoCodeqlError.new("boom", repo_id: @repo.id, twirp_error: :foo)
            ))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:auto_codeql_enable_all])
          end
        end

        test "does not retry on failed eligibility condition" do
          # eligibility check fails
          CodeScanning::AutoCodeql.any_instance.expects(:can_enable?).once
            .returns(SecurityProduct::Result.new(false, :some_eligibility_condition))

          # enablement never attempted
          CodeScanning::AutoCodeql.any_instance.expects(:on_enable).never

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:auto_codeql_enable_all])
          end
        end
      end

      context "when update type is auto_codeql_disable_all" do
        test "invokes service on_disable" do
          CodeScanning::AutoCodeql.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:auto_codeql_disable_all])
          end
        end
      end

      context "when update type is secret_scanning_enable_all" do
        test "invokes service on_enable" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::AdvancedSecurity.any_instance.expects(:enabled?).at_least_once.returns(true)
          SecurityProduct::TokenScanning.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_enable_all])
          end
        end

        test "instruments group backfill after last repo" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::AdvancedSecurity.any_instance.expects(:enabled?).at_least_once.returns(true)
          SecurityProduct::TokenScanning.any_instance.expects(:on_enable).at_least_once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          create_list(:private_repository, 3, owner: @org).each do |repo|
            RepositoryEnablementJob.perform_later(repository_id: repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_enable_all])
          end

          reset_hydro
          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest", count: 1)
          assert_hydro_published_partial({
            owner_id: @org.id,
            owner_scope: :ORGANIZATION_SCOPE,
            action: :START,
            backfill_type: :FULL,
            feature_flags: [
              SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
              SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
              SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
            ],
          }, schema: "token_scanning_service.v0.BackfillGroupRequest")
        end

        context "when emit_backfill_group_request is false" do
          test "does not instrument group backfill after last repo" do
            @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
            SecurityProduct::AdvancedSecurity.any_instance.expects(:enabled?).at_least_once.returns(true)
            SecurityProduct::TokenScanning.any_instance.expects(:on_enable).at_least_once
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

            create_list(:private_repository, 3, owner: @org).each do |repo|
              RepositoryEnablementJob.perform_later(repository_id: repo.id, actor_id: @actor.id,
                update_types: [:secret_scanning_enable_all], emit_backfill_group_request: false)
            end

            reset_hydro
            perform_enqueued_jobs only: RepositoryEnablementJob
            refute_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest")
          end
        end
      end

      context "when update type is secret_scanning_disable_all" do
        test "invokes service on_disable" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::TokenScanning.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_disable_all])
          end
        end

        test "instruments group backfill after last repo" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
          SecurityProduct::TokenScanning.any_instance.expects(:on_disable).at_least_once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          create_list(:private_repository, 3, owner: @org).each do |repo|
            RepositoryEnablementJob.perform_later(repository_id: repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_disable_all])
          end

          reset_hydro
          perform_enqueued_jobs only: RepositoryEnablementJob
          assert_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest", count: 1)
          assert_hydro_published_partial({
            owner_id: @org.id,
            owner_scope: :ORGANIZATION_SCOPE,
            action: :CANCEL,
            backfill_type: :FULL,
            feature_flags: [
              SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
              SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
              SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
            ],
          }, schema: "token_scanning_service.v0.BackfillGroupRequest")
        end

        context "when emit_backfill_group_request is false" do
          test "does not instrument group backfill after last repo" do
            @org.mark_advanced_security_as_purchased_for_entity(actor: @actor)
            SecurityProduct::TokenScanning.any_instance.expects(:on_disable).at_least_once
              .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

            create_list(:private_repository, 3, owner: @org).each do |repo|
              RepositoryEnablementJob.perform_later(repository_id: repo.id, actor_id: @actor.id,
                update_types: [:secret_scanning_disable_all], emit_backfill_group_request: false)
            end

            reset_hydro
            perform_enqueued_jobs only: RepositoryEnablementJob
            refute_hydro_messages(schema: "token_scanning_service.v0.BackfillGroupRequest")
          end
        end
      end

      context "when update type is secret_scanning_validity_checks_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::TokenScanning.any_instance.expects(:enabled?).returns(true)
          SecurityProduct::TokenScanningValidityChecks.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_validity_checks_enable_all])
          end
        end
      end

      context "when update type is secret_scanning_validity_checks_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::TokenScanningValidityChecks.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_validity_checks_disable_all])
          end
        end
      end

      context "when update type is secret_scanning_push_protection_enable_all" do
        test "invokes service on_enable" do
          SecurityProduct::TokenScanning.any_instance.expects(:enabled?).returns(true)
          SecurityProduct::TokenScanningPushProtection.any_instance.expects(:on_enable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_push_protection_enable_all])
          end
        end
      end

      context "when update type is secret_scanning_push_protection_disable_all" do
        test "invokes service on_disable" do
          SecurityProduct::TokenScanningPushProtection.any_instance.expects(:on_disable).once
            .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

          perform_enqueued_jobs only: RepositoryEnablementJob do
            RepositoryEnablementJob.perform_now(repository_id: @repo.id, actor_id: @actor.id,
              update_types: [:secret_scanning_push_protection_disable_all])
          end
        end
      end
    end

    context "retry" do
      test "basic retry conditions" do
        update_type = :advanced_security_enable_all

        # Because the `assert_retry_conditions` does not enqueue the job (it uses `perform_now`)
        # the counter will never be incremented. When it is later decremented, we cause an underflow.
        # Seed the counter here to correct for this.
        count_seed = [
          Aqueduct::Worker::JobKilled,
          Freno::Throttler::Error,
          *Resiliency::Response::UnavailableExceptions
        ].length
        SecurityProductsEnablement::KV.store.set("security_products:enablement_count:#{@org.business&.id || 0}:#{@org.id}:#{update_type}", count_seed.to_s)

        # Verify that the count is decremented and re-incremented for retry enqueues
        BlockedSettings::RepoCounter.any_instance.expects(:decrement).times(count_seed)
        BlockedSettings::RepoCounter.any_instance.expects(:increment).times(count_seed)

        assert_retry_conditions(job: RepositoryEnablementJob, args: [{
          repository_id: @repo.id,
          update_types: [update_type],
          actor_id: @actor.id,
        }])

        # Verify that when the job is enqueued for retry, the counter is also maintained
        assert_equal count_seed, block_counter(@org, update_type)
      end
    end

    context "hash lock" do
      test "disallows concurrent jobs for same repository" do
        assert_enqueued_jobs 1, only: RepositoryEnablementJob do
          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:advanced_security_enable_all])
          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:secret_scanning_enable_all])
          RepositoryEnablementJob.perform_later(repository_id: @repo.id, actor_id: @actor.id, update_types: [:auto_codeql_disable_all])
        end
      end
    end

    private

    def block_counter(org = @org, action = :job_test_action)
      key = "security_products:enablement_count:#{org.business&.id || 0}:#{org.id}:#{action}"
      (SecurityProductsEnablement::KV.store.get(key).value { nil } || 0).to_i
    end
  end
end
