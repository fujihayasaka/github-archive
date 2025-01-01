# typed: true
# frozen_string_literal: true

require "test_helper"

module GitHub::StreamProcessors
  module PagesDeploymentStatusProcessorSharedTest
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { PagesDeploymentStatusProcessorBaseTest }

    included do
      T.bind(self, T.class_of(PagesDeploymentStatusProcessorBaseTest))

      test "it update pages deployment status when succeed" do
        make_trusted_oauth_apps_owner
        pages_integration = create :github_pages_integration
        GitHub.stubs(:pages_github_app).returns(pages_integration)
        github_deployment = Deployment.create!(repository: @repo, sha: "12345678" * 5, creator: GitHub.pages_github_app.bot, environment: "github-pages", ref: @repo.page.source_branch)
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          deployment_id: "",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
          ],
          failed_hosts: [],
          github_deployment_id: github_deployment.id,
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 18 : 16)
        assert_equal 1, @page.deployments.count
        deployment = @page.deployments.first
        assert_equal message[:pages_build_version], deployment.revision
        assert_equal message[:successful_hosts].count, Page::Replica.count
        deployment_status = DeploymentStatus.where(deployment_id: github_deployment.id).first
        refute_nil deployment_status
        assert_equal "success", T.must(deployment_status).state
        assert_equal @page.url.to_s, T.must(deployment_status).environment_url
        Page::Replica.all.each do |replica|
          assert message[:successful_hosts].map { |host| host[:name] }.include? replica.host
        end
      end

      test "it update pages deployment status when succeed and remove legacy replica" do
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          deployment_id: "",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        now = Time.now
        Page::Replica.insert_all([
          { page_id: @page.id, pages_deployment_id: nil, host: "localhost", created_at: now, updated_at: now },
          { page_id: @page.id, pages_deployment_id: nil, host: "localhost2", created_at: now, updated_at: now },
          { page_id: @page.id, pages_deployment_id: nil, host: "localhost3", created_at: now, updated_at: now },
          { page_id: @page.id, pages_deployment_id: nil, host: "localhost", created_at: now, updated_at: now },
          { page_id: @page.id, pages_deployment_id: nil, host: "localhost2", created_at: now, updated_at: now },
        ])
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 7 : 4)
        assert_equal 1, @page.deployments.count
        deployment = @page.deployments.first
        assert_equal message[:pages_build_version], deployment.revision
        assert_equal message[:successful_hosts].count, Page::Replica.count
        Page::Replica.all.each do |replica|
          assert message[:successful_hosts].map { |host| host[:name] }.include? replica.host
        end
      end

      test "it updates pages deployment status when page has no source branch (workflow build_type)" do
        workflow_repo = create(:repository, owner: @repo_owner)
        create :page, repository_id: workflow_repo.id
        workflow_page = workflow_repo.page

        workflow_page.update_attribute(:build_type, 1)

        workflow_deployment = workflow_page.create_or_find_deployment_for(workflow_repo.default_branch)
        workflow_deployment.update_attribute(:revision, "previous")

        deployment_branch = "main"

        message = {
          repository_id: workflow_repo.id,
          global_id: workflow_repo.global_relay_id,
          pages_build_version: "123456",
          deployment_id: "",
          artifact_url: "https://download",
          environment: "production",
          ref: deployment_branch,
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: workflow_repo.id, owner_id: workflow_repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 7 : 4)
        assert_equal 2, workflow_page.deployments.count
        assert_equal message[:pages_build_version], workflow_page.reload.built_revision
        assert_equal message[:successful_hosts].count, Page::Replica.count
        Page::Replica.all.each do |replica|
          assert message[:successful_hosts].map { |host| host[:name] }.include? replica.host
        end
      end

      test "it update pages preview deployment status when succeed" do
        enable_feature_flag(:pages_preview_deployments)
        enable_feature_flag(:pages_preview_recycle_artifacts)
        pr_head_label = "#{@actor.login}:my-branch"
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          deployment_id: "",
          artifact_url: "https://download",
          environment: "preview",
          ref: pr_head_label,
          preview: true,
          preview_token: "1234abcdef",
          successful_hosts: [
            {
              name: "pages-dfs.net",
              non_voting: true
            },
            {
              name: "pages-dfs2.net",
              non_voting: true
            }
          ],
          failed_hosts: []
        }
        preview_deployment = @page.create_or_find_deployment_for(pr_head_label)
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 7 : 4)
        assert_equal 2, @page.deployments.count

        # Verify preview deployment is updated
        updated_preview_deployment = @page.deployments.find { |x| x.id == preview_deployment.id }
        assert_equal preview_deployment.id, updated_preview_deployment.id
        assert_equal message[:pages_build_version], updated_preview_deployment.revision
        refute_equal preview_deployment.revision, updated_preview_deployment.revision

        # Verify production deployment is untouched
        prod_deployment = @page.deployments.find { |x| x.id == @deployment.id }
        refute_equal message[:pages_build_version], prod_deployment.revision
        assert_equal @deployment.revision, prod_deployment.revision

        assert_equal message[:successful_hosts].count, Page::Replica.count
        Page::Replica.all.each do |replica|
          assert message[:successful_hosts].map { |host| host[:name] }.include? replica.host
        end
      end

      test "it not update pages deployment status when failed and exceed retried times" do
        make_trusted_oauth_apps_owner
        pages_integration = create :github_pages_integration
        GitHub.stubs(:pages_github_app).returns(pages_integration)
        github_deployment = Deployment.create!(repository: @repo, sha: "12345678" * 5, creator: GitHub.pages_github_app.bot, environment: "github-pages", ref: @repo.page.source_branch)
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "23456",
          deployment_id: "",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [],
          retried_times: 2,
          failed_hosts: [
            {
              name: "pages-dfs3.net",
              non_voting: true
            }
          ],
          github_deployment_id: github_deployment.id,
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "23456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:fail_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 14 : 12)
        assert_equal 1, @page.deployments.count
        deployment = @page.deployments.first
        assert_equal "previous", deployment.revision # Previous deployment will have been recycled.
        assert_equal 0, Page::Replica.count
        assert_equal "failure", DeploymentStatus.where(deployment_id: github_deployment.id).first&.state
      end

      test "it kicked off retry when deployment failed and not exceed retried times" do
        pages_build_version = "23456"
        artifact_url = "https://download"
        environment = "preview"
        pr_head_label = "#{@actor.display_login}:my-branch"
        preview_token = "1234abcdef"
        retried_times = 1
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: pages_build_version,
          deployment_id: "",
          artifact_url: artifact_url,
          environment: environment,
          ref: pr_head_label,
          preview: true,
          preview_token: preview_token,
          successful_hosts: [],
          retried_times: retried_times,
          failed_hosts: [
            {
              name: "pages-dfs3.net",
              non_voting: true
            }
          ],
          type: 1,
          sub_dir: "/docs",
          nwo: "#{@repo.nwo}",
        }
        hosts = [{
          name: "pages-dfs3.net",
          non_voting: true
        }]
        expected_payload = {
          hosts: hosts,
          path: GitHub::Routing.dpages_storage_path(@page.id, revision: pages_build_version),
          artifact_url: artifact_url,
          environment: environment,
          pages_build_version: pages_build_version,
          deployment_id: "",
          global_id: @repo.global_relay_id,
          repo_id: @repo.id,
          writing_non_voting: false,
          ref: pr_head_label,
          preview: true,
          preview_token: preview_token,
          retried_times: retried_times + 1,
          deployment_type: 1,
          sub_dir: "/docs",
          nwo: "#{@repo.nwo}",
          github_deployment_id: 0,
        }

        @page.create_or_find_deployment_for(pr_head_label)

        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: pages_build_version, repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        GitHub::Pages::Replicator.any_instance.expects(:hosts_with_datacenter).returns(hosts)
        mock_client = mock("aqueduct_client")
        mock_client.expects(:send_job).with(equals(
          {
            payload: expected_payload.to_json,
            queue: "pages-deployer",
            redelivery_timeout_secs: 20
          }
        )).returns({ job_id: "123" }).once
        GitHub::Pages::PagesDeployerClient.clear_default_aqueduct_client
        GitHub.stubs(:build_aqueduct_client).returns(mock_client)
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 5 : 3)
      end

      test "it recycled when deployment succeed" do
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        storage_path = GitHub::Routing.dpages_storage_path(@page.id, revision: @previous_revision)

        t = Time.now
        Time.stubs(:now).returns(t)

        # the localhost should be exclude from here.
        assert_enqueued_with(job: PageRecycleJob, args: [[], storage_path, @page.id, t], queue: "background_destroy") do
          process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 7 : 4)
        end
      end unless GitHub.enterprise?

      test "it cleaned previous artifact when deployment succeed" do
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")

        # the localhost should be exclude from here.
        assert_enqueued_with(job: PageRecycleArtifactJob, args: [@page.id], queue: "background_destroy") do
          process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 7 : 4)
        end
      end unless GitHub.enterprise?

      test "it cleaned artifact when preview deployment succeeds" do
        enable_feature_flag(:pages_preview_deployments)
        enable_feature_flag(:pages_preview_recycle_artifacts)
        pr_head_label = "#{@actor.display_login}:my-branch"
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          artifact_url: "https://download",
          artifact_id: 5678,
          environment: "preview",
          ref: pr_head_label,
          preview: true,
          preview_token: "1234abcdef",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        Page.any_instance.expects(:complete_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")

        # the localhost should be exclude from here.
        assert_enqueued_with(job: PageRecycleArtifactJob, args: [@page.id, 5678], queue: "background_destroy") do
          process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 8 : 5)
        end
      end unless GitHub.enterprise?

      test "it skipped deployment if deployment cancelled" do
        deployment_id = "23456790123"
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: deployment_id,
          deployment_id: "",
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [{
            name: "pages-dfs3.net",
            non_voting: true
          }],
          failed_hosts: []
        }
        Page::Twirp::RequestClient.any_instance.expects(:get_status)
          .with(deployment_id: deployment_id, repository_id: @repo.id, owner_id: @repo.owner_id).returns("deployment_cancelled")
        Page::Twirp::RequestClient.any_instance.expects(:clear_status)
          .with(deployment_id: deployment_id, repository_id: @repo.id)
        Page.any_instance.expects(:fail_build).once
        publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
        process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 4 : 2)
        assert_equal 1, @page.deployments.count
        deployment = @page.deployments.first
        assert_equal "previous", deployment.revision # Previous deployment will have been recycled.
        assert_equal 0, Page::Replica.count
      end

      test "it enqueued with correct information to deployment-events when succeed" do
        enable_feature_flag(:post_deployment_hydro_event)
        message = {
          repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: "123456",
          artifact_url: "https://download",
          environment: "production",
          aqueduct_message: "aqueduct message",
          artifact_hash: "artifact_hash",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
        build = Page::Build.track(@repo.page, pusher: @repo_actor)
        build.complete!((Time.now - T.cast(build.updated_at, Time)) * 1_000)
        Page::Twirp::RequestClient.any_instance.expects(:get_status).with(deployment_id: "123456", repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
        # Purging doesn't happen in multi-tenant environments
        unless GitHub.multi_tenant_enterprise?
          Page::Twirp::RequestClient.any_instance.expects(:update_status)
            .with(deployment_id:  "123456", repository_id: @repo.id, status: "purging_cdn").once
          Fastly.any_instance.expects(:purge_cdn).once
        end

        checks = ->() {
          publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
          process_messages!(allowed_primary_query_count: GitHub.multi_tenant_enterprise? ? 19 : 13)

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@repo_actor),
            repository_owner: Hydro::EntitySerializer.user(@repo_owner),
            page: Hydro::EntitySerializer.page(@repo.reload.page),
            aqueduct_message: message[:aqueduct_message],
            artifact_hash: message[:artifact_hash],
          }, schema: "github.v1.RepositoryPagesActionBuild")
        }

        if GitHub.multi_tenant_enterprise?
          # We need to freeze time in multi-tenant environments because Hydro::EntitySerializer.user avatar_url token is generated based on Time.now
          Timecop.freeze do
            checks.call
          end
        else
          checks.call
        end
      end unless GitHub.enterprise?
    end
  end

  class PagesDeploymentStatusProcessorBaseTest < GitHub::TestCase
    include HydroTestHelpers

    def process_messages!(rescue_from_standard_error: true, **kwargs)
      run_processor(
        GitHub::StreamProcessors::PagesDeploymentStatusProcessor.new(
          rescue_from_standard_error: rescue_from_standard_error
        ),
        **kwargs
      )
    end
  end

  class PagesDeploymentStatusProcessorTest < PagesDeploymentStatusProcessorBaseTest
    include PagesDeploymentStatusProcessorSharedTest

    fixtures do
      @owner = create(:user)
      @repo_owner = @owner
      @actor = create(:user)
      @repo = create(:repository, owner: @owner, from_example: :pages)
      @repo_actor = @owner
      create :page, repository_id: @repo.id
      @page = @repo.page
      @deployment = @page.create_or_find_deployment_for(@page.source_branch)
      @previous_revision = "previous"
      @deployment.update_attribute(:revision, @previous_revision)
    end

    setup do
      Spokesd.enable_spokesd
    end

    test "it purges cdn when deployment succeed" do
      deployment_id = "123456"
      Page::Twirp::RequestClient.any_instance.expects(:update_status)
        .with(deployment_id: deployment_id, repository_id: @repo.id, status: "purging_cdn").once
      Page::Twirp::RequestClient.any_instance.expects(:get_status)
        .with(deployment_id: deployment_id, repository_id: @repo.id, owner_id: @repo.owner_id).returns("updating_pages")
      Fastly.any_instance.expects(:purge_cdn).with(@page.fastly_purge_key).once
      message = {
        repository_id: @repo.id,
        global_id: @repo.global_relay_id,
        pages_build_version: deployment_id,
        artifact_url: "https://download",
        environment: "production",
        successful_hosts: [
        {
          name: "pages-dfs.net",
          non_voting: true
        },
        {
          name: "pages-dfs2.net",
          non_voting: true
        }
      ],
        failed_hosts: []
      }

      publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
      process_messages!(allowed_primary_query_count: 8)
    end unless GitHub.enterprise?

    test "it does not purge cdn on enterprise" do
      deployment_id = "123456"
      Fastly.any_instance.expects(:purge_cdn).never
      message = {
        repository_id: @repo.id,
          global_id: @repo.global_relay_id,
          pages_build_version: deployment_id,
          artifact_url: "https://download",
          environment: "production",
          successful_hosts: [
          {
            name: "pages-dfs.net",
            non_voting: true
          },
          {
            name: "pages-dfs2.net",
            non_voting: true
          }
        ],
          failed_hosts: []
        }
      publish_hydro_message(message, skip_github_tenant_header: true, schema: "pages_deployer.v0.DeploymentStatus")
      process_messages!(allowed_primary_query_count: 8)
    end if GitHub.enterprise?
  end

  class PagesDeploymentStatusProcessorMultiTenantTest < PagesDeploymentStatusProcessorBaseTest
    include PagesDeploymentStatusProcessorSharedTest

    fixtures do
      on_multi_tenant_enterprise { @business = create :business, :enterprise_managed_business }
      on_multi_tenant_enterprise tenant: @business do
        @owner = create(:emu, :owner, business: @business)
        @actor = create(:emu, business: @business)
        org = create :organization, business: @business, admin: @owner
        @repo_owner = org
        @repo = create(:repository, owner: org, from_example: :pages)
        @repo.add_member(@owner)
        @repo_actor = @owner
        create :page, repository_id: @repo.id
        @page = @repo.page
        @deployment = @page.create_or_find_deployment_for(@page.source_branch)
        @previous_revision = "previous"
        @deployment.update_attribute(:revision, @previous_revision)
      end
    end

    setup do
      Spokesd.enable_spokesd
      on_multi_tenant_enterprise(tenant: @business)
    end
  end
end
