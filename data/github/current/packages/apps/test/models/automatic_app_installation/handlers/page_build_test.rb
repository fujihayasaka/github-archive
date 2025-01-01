# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::PageBuildTest < GitHub::TestCase
  include PageHelper

  fixtures do
    @app = create(
      :integration,
      name: "Don't worry, be happy",
      default_permissions: { "contents" => :read },
    )

    @page = create(:page, :built)
    @repo = @page.repository
    @pusher = @repo.owner
    @repo_without_pages = create(:repository, :minimal)
    @git_ref_name = @page.source
    @options = {
      page_id: @page.id,
      pusher_id: @pusher.id,
      git_ref_name: @git_ref_name,
    }
    @trigger = create(:integration_install_trigger, integration: @app, install_type: :page_build)
  end

  context "page_build trigger" do
    test "installs integration when feature flag is enabled and repo has pages" do
      enable_feature_flag(:pages_github_app, @repo)
      handler = AutomaticAppInstallation::Handlers::PageBuild.new(**args)
      Timecop.freeze do
        expected_args = [
          @repo.owner_id,
          @trigger.integration.id,
          @trigger.id,
          [@repo.id],
          @options.merge(
            {
              "enqueued_timestamp" => Time.now.to_i,
              :entry_point => :automatic_app_installation_handler_page_build
            }
          )
        ]
        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: expected_args do
          handler.install_integration
        end
      end
    end

    test "does not install when feature flag is disabled" do
      disable_feature_flag(:pages_github_app)
      handler = AutomaticAppInstallation::Handlers::PageBuild.new(**args)

      handler.install_integration
      assert_no_enqueued_jobs only: InstallAutomaticIntegrationsJob
    end

    test "does not install when repo doesn't have pages" do
      enable_feature_flag(:pages_github_app, @repo)
      handler = AutomaticAppInstallation::Handlers::PageBuild.new(**args(pages_repo: false))

      handler.install_integration
      assert_no_enqueued_jobs only: InstallAutomaticIntegrationsJob
    end
  end

  context "after_integration_installed" do
    test "invokes :publish on the page" do
      Page.expects(:find_by!).with(id: @page.id).returns(@page)
      User.expects(:find_by!).with(id: @pusher.id).returns(@pusher)
      @page
        .expects(:publish)
        .with(@pusher, git_ref_name: @git_ref_name)

      AutomaticAppInstallation::Handlers::PageBuild.after_integration_installed(options: @options)
    end

    test "fails silently and reports when ActiveRecord::RecordNotFound is raised" do
      Page.expects(:find_by!).with(id: @page.id).raises(ActiveRecord::RecordNotFound)
      Failbot.expects(:report!)

      AutomaticAppInstallation::Handlers::PageBuild.after_integration_installed(options: @options)
    end
  end

  def args(pages_repo: true)
    {
      install_triggers: [@trigger],
      originator: @options,
      actor: pages_repo ? @repo : @repo_without_pages,
    }
  end
end
