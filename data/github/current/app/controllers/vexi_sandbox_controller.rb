# typed: strict
# frozen_string_literal: true

require "active_job/job_class_actor"

class VexiSandboxController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  # CAP not required, this is an employee-only controller for testing the Vexi Feature Flag Client
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :only_allow_staff_in_dotcom_or_stafftools_tenant_in_proxima

  preload_features [
    :vexi_sandbox_no_proxy_test_flag_1
  ].freeze

  helper_method :flipper_enabled_check, :flipper_square_bracket_check, :flipper_actor_check, :permitted_params

  NAV_OPTIONS = T.let(%w[landing vexi_with_preload vexi_with_preload_directly_from_adapter vexi_test vexi_debug vexi_actors], T::Array[String])

  VEXI_FEATURE_FLAGS = T.let([
    :vexi_sandbox_no_proxy_test_flag_fully_disabled,
    :vexi_sandbox_no_proxy_test_flag_100_of_actors,
    "vexi_sandbox_no_proxy_test_flag_100_of_calls",
    :vexi_sandbox_no_proxy_test_flag_custom_group,
    :vexi_sandbox_no_proxy_test_flag_does_not_exist,
  ], T::Array[T.any(Symbol, String)])

  FLIPPER_FEATURE_FLAGS = T.let([
    :vexi_sandbox_test_via_flipper_proxy_1,
    :vexi_sandbox_test_via_flipper_proxy_2,
    :vexi_sandbox_test_via_flipper_proxy_3,
  ], T::Array[Symbol])

  class FakeFlipperActor
    include GitHub::FlipperActor
    include FeatureFlag::IFeatureTarget

    sig { params(id: String).void }
    def initialize(id)
      @id = id
    end

    sig { override.returns(String) }
    def flipper_id
      "FlipperActor:#{@id}"
    end

    sig { override.params(flag: T.any(String, Symbol), memoize: T::Boolean).returns(T::Boolean) }
    def feature_enabled?(flag, memoize: false)
      FeatureFlag.vexi.enabled?(flag, self, default: false)
    end

    sig { override.returns(T::Hash[String, T::Boolean]) }
    def memoized_custom_gates
      {}
    end
  end

  sig { void }
  def index
    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil, label: "Vexi Sandbox")

    page = params[:nav_option] || "landing"
    if !NAV_OPTIONS.include?(page)
      page = "landing"
    end

    vexi_checks = []
    flipper_checks = []

    if page == "landing"
      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_square_bracket_check(feature_flag_name, FakeFlipperActor.new("1337"))
        checks << flipper_actor_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, FakeFlipperActor.new("1337"))
      end
    elsif page == "vexi_with_preload"
      FeatureFlag.vexi.preload(
        VEXI_FEATURE_FLAGS + FLIPPER_FEATURE_FLAGS,
        fetch_directly_from_adapter: false,
        cache_without_expiry: true,
        instrumentation_properties: { "code.namespace": self.class.name&.underscore },
      )

      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, current_user)
      end
    elsif page == "vexi_with_preload_directly_from_adapter"
      FeatureFlag.vexi.preload(
        VEXI_FEATURE_FLAGS + FLIPPER_FEATURE_FLAGS,
        fetch_directly_from_adapter: true,
        cache_without_expiry: true,
        instrumentation_properties: { "code.namespace": self.class.name&.underscore },
      )

      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end

      flipper_checks = FLIPPER_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << flipper_enabled_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name)
        checks << flipper_square_bracket_check(feature_flag_name, current_user)
        checks << flipper_actor_check(feature_flag_name, current_user)
      end
    elsif page == "vexi_test"
      vexi_checks = VEXI_FEATURE_FLAGS.each_with_object([]) do |feature_flag_name, checks|
        checks << vexi_check(feature_flag_name)
        checks << vexi_check(feature_flag_name, [current_user])
      end
    elsif page == "vexi_debug" && permitted_params[:feature_flag_name].present?
      feature_flag_name = permitted_params[:feature_flag_name]

      unless feature_flag_name.start_with?("vexi_sandbox_")
        return redirect_to(_vexi_sandbox_index_path(nav_option: page))
      end

      actor_names = permitted_params[:actors].split(",").map(&:strip)
      actors = actor_names.map do |actor_name|
        GitHub::Resources.find_by_uri(actor_name)
      end.compact

      vexi_checks = [vexi_check(feature_flag_name, actors)]
    elsif page == "vexi_actors"
      actors = [
        ClusterAsActor.new("test_cluster"), # app/jobs/cluster_as_actor.rb
        Platform::MutationActor.new(Platform::Mutations::CreateIssue), # app/platform/mutation_actor.rb
        ActiveJob::JobClassActor.new(HydroMessageJob), # lib/active_job/job_class_actor.rb
        Alloy::AppActor.new("test_app"), # packages/alloy/app/public/alloy/app_actor.rb
        Events::ParentAsActor.new("test_parent"), # lib/events/parent_as_actor.rb
        GitHub::FlipperHost.new("test_host"), # lib/github/flipper_host.rb
        GitHub::FlipperRole.new("test_role"), # lib/github/flipper_role.rb
        GitHub::FlipperSite.new("test_site"), # lib/github/flipper_site.rb
        GitHub::Aqueduct::CompositeBackend::Actor.new(hostname: "test_host", pid: 1), # lib/github/aqueduct/composite_backend.rb # Note: This includes a value for the minute so will not be stable
        # GitHub::DGit::Delegate,  # lib/github/dgit/delegate.rb
        GitHub::DGit::Util::NetworkIdActor.new("test_network_id"), # lib/github/dgit/util.rb
        GitHub::Unsullied::Wiki.new(Repository.new(id: 1)), # lib/github/unsullied/wiki.rb
        Stratocaster::EventTypeActor.new("test_event_type", "test_action"), # lib/stratocaster/event_type_actor.rb
        Environment.new(id: 1), # packages/actions/app/models/environment.rb
        Business.new(id: 1), # packages/business/app/models/business.rb
        OauthApplication.default, # packages/app_security/app/models/oauth_application.rb
        OauthAuthorization.new(id: 1), # packages/app_security/app/models/oauth_authorization.rb
        UserSession.new(id: 1), # packages/app_security/app/models/user_session.rb
        IntegrationInstallation.new(id: 1), # packages/apps/app/models/integration_installation.rb
        Integration.new(id: 1), # packages/apps/app/models/integration.rb
        ScopedIntegrationInstallation::RepositoryFlipperActor.new(1), # packages/apps/app/models/scoped_integration_installation/repository_flipper_actor.rb
        Customer.new(id: 1), # packages/billing/app/models/customer.rb
        Billing::ZuoraWebhook.new(id: 1), # packages/billing/app/models/billing/zuora_webhook.rb
        Copilot::CopilotApi::IntegrationActor.new("test_integration"), # packages/copilot/app/models/copilot/copilot_api/integration_actor.rb
        Copilot::CopilotApi::TrackingIdActor.new("test_tracking_id"), # packages/copilot/app/models/copilot/copilot_api/tracking_id_actor.rb
        Storage::Uploadable::UploadableFlipperFlag.new(FakeUploadable.new), # packages/data/app/models/storage/uploadable/uploadable_flipper_flag.rb
        Gist.new(id: 1), # packages/gist/app/models/gist.rb
        FlipperSession.new(1), # packages/management_tools/app/models/flipper_session.rb
        Repository.new(id: 1), # packages/management_tools/app/models/repository/feature_flags_dependency.rb
        # TradeControls::AbstractTradeScreeningDependency # packages/management_tools/app/models/trade_controls/abstract_trade_screening_dependency.rb this looks to be just included in other models (User, Org, Business) and not initialized directly
        User::CurrentVisitorActor.new("GH1.1.1234.1234"), # packages/management_tools/app/models/user/current_visitor_actor.rb
        User::EmailSuffixActor.from_email_address("monalisa+test.o2MeJz9dp@github.com"), # packages/management_tools/app/models/user/email_suffix_actor.rb
        current_user, # packages/management_tools/app/models/user/feature_flag_methods.rb
        NotificationSummary.new(list_id: 1), # packages/notifications/app/models/notification_summary.rb
        Newsies::NotificationEntry.new(user_id: 1), # packages/notifications/app/models/newsies/notification_entry.rb
        Newsies::SavedNotificationEntry.new(user_id: 1), # packages/notifications/app/models/newsies/saved_notification_entry.rb
        Team.new(id: 1), # packages/orgs/app/models/team.rb
        Organization.new(id: 1), # packages/orgs/app/models/organization/feature_flag_dependency.rb
        MemexProject.new(id: 1), # packages/planning/app/models/memex_project.rb
        # Profiles::User::BaseLayoutData # packages/profiles/app/models/profiles/user/base_layout_data.rb
        UserProgrammaticAccess.new(id: 1), # packages/programmatic_access/app/models/user_programmatic_access.rb
        PersonalReminder.new(id: 1), # packages/pull_requests/app/models/personal_reminder.rb
        Reminder.new(id: 1), # packages/pull_requests/app/models/reminder.rb
        BulkReposIndexJob::AdminnedOrgIdActor.new(1), # packages/repositories/app/jobs/bulk_repos_index_job.rb
        RepositoryNetwork.new(id: 1), # packages/repositories/app/models/repository_network.rb
        Repository.new(id: 1), # packages/repositories/app/models/repository.rb
        Repositories::AssociatedRepositoriesDependency::AssociatedRepositories::AdminnedOrgIdActor.new(1), # packages/repositories/app/models/repositories/associated_repositories_dependency.rb
        Repositories::Domain::BadActorGate::DomainMethodActor.new("test_domain", :test_method, 1, 1), # packages/repositories/app/public/repositories/domain/bad_actor_gate.rb
        RepositoryVulnerabilityAlert::RepositoryFlipperActor.new(1), # packages/security_products/app/models/repository_vulnerability_alert.rb
        SecurityCenter::FlipperActorAdapters::Repository.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        SecurityCenter::FlipperActorAdapters::Organization.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        SecurityCenter::FlipperActorAdapters::Business.new(1), # packages/security_products/app/models/security_center/flipper_actor_adapters.rb
        Vulnerability.new(id: 1), # packages/security_products/app/models/vulnerability/shared_methods.rb
        Hook.new(id: 1), # packages/webhooks/app/models/hook.rb
        Hook::ParentAsActor.new("test_parent"), # packages/webhooks/app/models/hook.rb
        Hook::EventAsActor.new("test_event"), # packages/webhooks/app/models/hook.rbs
      ]

      vexi_checks = actors.each_with_object([]) do |actor, checks|
        flag_name = "vexi_sandbox_all_actors"
        checks << vexi_check(flag_name, [actor])
      end
    end

    render "vexi/sandbox/index", locals: { page: page, nav_options: NAV_OPTIONS, vexi_checks: vexi_checks, flipper_checks: flipper_checks }
  end

  private

  sig { returns(ActionController::Parameters) }
  memoize def permitted_params
    params.permit(:nav_option, :feature_flag_name, :actors, :submit, :cache_tracer, :ff_cache_tracer)
  end

  # Wraps Vexi enabled check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actors: T::Array[GitHub::VexiActor]).returns(T::Hash[Symbol, String]) }
  def vexi_check(feature_flag, actors = []) # rubocop:todo GitHub/UseRestfulActions
    code = if actors.present?
      "FeatureFlag.vexi.enabled?(#{feature_flag}, #{actors.map(&:vexi_id).join(", ")}))"
    else
      "FeatureFlag.vexi.enabled?(#{feature_flag})"
    end

    # Using T.unsafe here because of the Splat parameter
    # Workaround for https://sorbet.org/docs/error-reference#7019
    enabled = T.unsafe(FeatureFlag.vexi).enabled?(feature_flag, *actors, default: false) ? "enabled" : "disabled"

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps GitHub.flipper.enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String)).returns(T::Hash[Symbol, String]) }
  def flipper_enabled_check(feature_flag)
    code = "GitHub.flipper.enabled?(#{feature_flag})"
    enabled = GitHub.flipper.enabled?(feature_flag) ? "enabled" : "disabled"
    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps GitHub.flipper[:feature].enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actor: T.nilable(GitHub::FlipperActor)).returns(T::Hash[Symbol, String]) }
  def flipper_square_bracket_check(feature_flag, actor = nil)
    enabled = "disabled"
    code = ""
    if actor.nil?
      code = "GitHub.flipper[#{feature_flag}].enabled?"
      enabled = GitHub.flipper[feature_flag].enabled? ? "enabled" : "disabled"
    else
      code = "GitHub.flipper[#{feature_flag}].enabled?(#{actor.flipper_id})"
      enabled = GitHub.flipper[feature_flag].enabled?(actor) ? "enabled" : "disabled"
    end

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  # Wraps actor.feature_enabled?() check and will output the feature flag name and also if it's enabled or there's an exception
  sig { params(feature_flag: T.any(Symbol, String), actor: FeatureFlag::IFeatureTarget).returns(T::Hash[Symbol, String]) }
  def flipper_actor_check(feature_flag, actor)
    code = "(#{T.unsafe(actor).flipper_id}).feature_enabled?(#{feature_flag})"
    enabled = actor.feature_enabled?(feature_flag) ? "enabled" : "disabled"

    { code: code, feature_flag: feature_flag, result: enabled }
  rescue => e # rubocop:disable Lint/GenericRescue
    Failbot.report!(e)
    { code: code, feature_flag: feature_flag, result: e.message }
  end

  sig { void }
  def only_allow_staff_in_dotcom_or_stafftools_tenant_in_proxima
    # Don't allow in GHES at all (this is also guarded in the routes)
    render_404 if GitHub.enterprise?

    # If we're in a multi-tenant enterprise, only allow staff in the stafftools tenant.
    # We aren't checking for employee status here because we aren't employees in these tenants.
    # Being logged into the stafftools tenant is enough since only staff have access to it.
    if GitHub.multi_tenant_enterprise?
      render_404 unless GitHub::CurrentTenant.stafftools_tenant?
      render_404 unless logged_in?
    else
      # Otherwise, only allow staff in dotcom
      employee_only
    end
  end

  class FakeUploadable
    sig { returns(String) }
    def storage_migration_id
      "test_migration_id"
    end
  end
end
