# typed: true
# frozen_string_literal: true

module GitHub
  class Plan
    class Error < StandardError; end
    class EntitlementError < StandardError; end

    class UnknownFeatureError < ArgumentError
      def initialize(unknown_feature, allowed_features)
        @unknown_feature = unknown_feature
        @allowed_features = allowed_features
      end

      def message
        "Unknown feature name passed: #{@unknown_feature.inspect}. " \
          "Expecting one of #{@allowed_features.inspect}"
      end
    end

    include Comparable
    include GitHub::Plan::ZuoraDependency
    include ::Scientist

    # For all intents and purposes, we consider this to be the "magic" number to indicate the plan
    # has unlimited private repos.
    UNLIMITED_REPOS   = 9999

    FREE              = "free"
    FREE_WITH_ADDONS  = "free_with_addons"
    ENTERPRISE        = "enterprise"
    BUSINESS          = "business"
    BUSINESS_PLUS     = "business_plus"
    PRO               = "pro"
    EMU_USER          = "emu_user"

    # Used in user sign up flow to differentiate user free plan from organization free plan
    TEAM_FREE_PLAN_NAME = "team_free"

    # This is a legacy plan that should never be offered, ever.
    ENGINEYARD        = "engineyard"

    FEATURES = {
      attestations: "Enables storing attestations for repositories.",
      codeowners: "Enables automatic review requests and enforcement based on a CODEOWNERS file.",
      insights: "Enables insights tab for repositories.",
      projectsv2_charts_basic: "Enables basic features for creating custom, current state charts in project insights.",
      projectsv2_insights_limited: "Enables limited preview features for creating custom, historical charts in project insights.",
      projectsv2_insights_basic: "Enables basic features for creating custom, historical charts in project insights.",
      pages: "Enables Pages site generated from the repository.",
      private_pages: "Enables Pages site generated from the repository to be private.",
      protected_branches: "Enables protected branches.",
      protected_tags: "Enables protected tags.",
      repo_access_export: "Enables the ability to export a list of users with access to a repository in an organization.",
      fine_grained_permissions: "Enables granular permissions beyond read, write, and admin.",
      custom_roles: "Enables granular roles beyond read, write, and admin, with the use of fine grained permissions.",
      repos: "Enables the creation of repositories.",
      wikis: "Enables wikis tab for repositories.",
      draft_prs: "Enables draft pull requests.",
      display_commenter_full_name: "Enables displaying comment author's full name",
      display_verified_domain_emails: "Enables the ability for organization owners to view the verified domain emails of organization members.",
      restrict_notification_delivery: "Enables the ability to restrict email notification delivery to verified domain emails in an organization.",
      audit_log_api: "Enables GraphQL API access to audit log entries.",
      ssh_certificates: "Enables users to authenticate with organization/enterprise managed SSH certificate authorities.",
      ip_allowlist: "Enables defining an allowed list of IP addresses for access to resources owned by an enterprise or organization.",
      custom_key_links: "Enables autolink references in the owner's repositories.",
      reminders: "Enables Scheduled and Realtime Reminders for organizations.",
      team_review_requests: "Enables teams to be requested for review on a pull request.",
      allow_codespaces: "Enables the ability to use Codespaces if the feature flag is enabled",
      insights_self_service: "Enables self service for organization level Insights",
      environment_protection_rules: "Environment protection rules",
      environment_protection_secrets: "Environment deployment branches and secrets",
      private_secrets_and_variables: "Access to secrets and variables for private/internal repositories in org",
      merge_queue: "Enables merge queues.",
      enterprise_rulesets: "Enterprise rulesets for repo security. Advanced features like org-level rules, commit metadata and rule insights.",
      rulesets: "Repository rulesets for repo security.",
    }.freeze

    LIMITS = {
      collaborators: "The number of collaborators allowed on a repository.",
      repos: "The number of owned repositories allowed.",
      raw_blob_access_expires_in_seconds: "The number in seconds a raw blob will be available.",
      media_blob_max_size: "The maximum size in bytes of an LFS blob.",
      issue_pr_assignees: "The maximum number of users allowed to be assigned to an issue or pull request.",
      manual_review_requests: "The maximum number of users allowed to be requested for review on a pull request.",
      projectsv2_auto_add_workflows: "The maximum number of auto-add workflows allowed for a project.",
    }.freeze

    FEATURE_INFORMATION = {
      business_plus: [
        { title: "Data residency", description: "GitHub Enterprise Cloud offers a multi-tenant enterprise SaaS solution on Microsoft Azure, allowing you to choose a regional cloud deployment for data residency, so your in-scope data is stored at rest in a designated location. <a href='https://github.com/account/enterprises/new'>Start a free 30 day trial</a> today or <a href='/enterprise/contact/data-residency'>contact our sales team</a> for more information." },
        { title: "Enterprise Managed Users", description: "Own and control the user accounts of your enterprise members through your identity provider (IdP)." },
        { title: "User provisioning through SCIM", description: "Automatically invite members to join your organization when you grant access on your IdP. If you remove a member's access to your GitHub organization on your SAML IdP, the member will be automatically removed from the GitHub organization." },
        { title: "Enterprise Account to centrally manage multiple organizations", description: "GitHub Enterprise Cloud includes the option to create an enterprise account, which enables collaboration between multiple organizations, gives administrators a single point of visibility and management and brings license cost savings for identical users in multiple organizations." },
        { title: "Environment protection rules", description: "When a workflow job references an environment, the job won't start until all of the environment's protection rules pass." },
        { title: "Repository rules", description: "Enforce branch and tag protections, as well as push rules across your enterprise. Rule insights allow you to assess impact of rules before and during enforcement." },
        { title: "Audit Log API", description: "As a GitHub Enterprise Cloud organization administrator, you can now access log events using our GraphQL API and monitor the activity in your organization."  },
        { title: "SOC1, SOC2, type 2 reports annually", description: "GitHub offers AICPA System and Organization Controls (SOC) 1 Type 2 and SOC 2 Type 2 reports with IAASB International Standards on Assurance Engagements, ISAE 3000, and ISAE 3402." },
        { title: "FedRAMP Tailored Authority to Operate (ATO)", description: "Government users can host projects on GitHub Enterprise Cloud with the confidence that our platform meets the low impact software-as-a-service (SaaS) baseline of security standards set by our U.S. federal government partners." },
        { title: "SAML single sign-on", description: "Use an identity provider to manage the identities of GitHub users and applications." },
        { title: "Advanced auditing", description: "Quickly review the actions performed by members of your organization. Keep copies of audit log data to ensure secure IP and maintain compliance for your organization." },
        { title: "GitHub Connect", description: "Share features and workflows between your GitHub Enterprise Server instance and GitHub Enterprise Cloud." }
      ]
    }.freeze

    attr_reader :name, :features, :limits
    attr_writer :receipt_effective_on
    attr_accessor :account

    def self.free(account: nil, effective_at: nil)
      find!("free", account: account, effective_at: effective_at)
    end

    def self.free_with_addons(account: nil, effective_at: nil)
      find!("free_with_addons", account: account, effective_at: effective_at)
    end

    def self.enterprise(account: nil, effective_at: nil)
      find!("enterprise", account: account, effective_at: effective_at)
    end

    def self.business(account: nil, effective_at: nil)
      find!("business", account: account, effective_at: effective_at)
    end

    def self.business_plus(account: nil, effective_at: nil)
      find!("business_plus", account: account, effective_at: effective_at)
    end

    def self.pro(account: nil, effective_at: nil)
      find!("pro", account: account, effective_at: effective_at)
    end

    # Override as_json to exclude the account instance variable
    #
    # The account hash references the GitHub::Plan, which creates an infinite loop
    #
    # Returns a Hash of the GitHub::Plan
    def as_json(options = {})
      super({ except: ["account"] }.merge(options))
    end

    # Find a Plan by its name/slug
    #
    # effective_at: (Optional) Date that the user signed up for the plan.
    # Determines which rate they get if a plan has multiple rate_plans.
    # Defaults to today
    #
    # account: (Optional) Account that will be used to check if a feature flag has been enabled, used to
    # enable or disable pricing changes, and to check if an account is on an Enterprise Trial.
    #
    # Returns a Plan or nil
    def self.find(name, effective_at: nil, account: nil)
      target_name = name.to_s.downcase
      plan = self.all.detect { |plan| plan.name.to_s.downcase == target_name }.dup
      plan&.effective_at = effective_at
      plan&.account = account
      plan
    end

    # Like find, except we raise if a matching plan isn't found
    def self.find!(name, effective_at: nil, account: nil)
      find(name, effective_at: effective_at, account: account) ||
        raise(Error, "No plan found for #{name}")
    end

    def self.org_plans
      @org_plans ||= all.select { |p| p.org_plan? }
    end

    def self.default_plan(account: nil, effective_at: nil)
      find!(GitHub.default_plan_name, account: account, effective_at: effective_at)
    end

    def self.all_org_plans
      @all_org_plans ||= all.select { |p| (p.org_plan? || p.hidden_org_plan?) && p.name != ENGINEYARD }
    end

    def self.non_free_org_plans
      org_plans.reject { |plan| [FREE, ENTERPRISE].include?(plan.name) }
    end

    def self.all_non_free_org_plans
      all_org_plans.reject { |plan| [FREE, ENTERPRISE].include?(plan.name) }
    end

    def self.user_plans
      @user_plans ||= all.select { |p| p.user_plan? }
    end

    def self.all_user_plans
      @all_user_plans ||= all.
        select { |p| p.user_plan? || p.hidden_user_plan? }.
        reject { |p| %w(pico nano pro).include?(p.name) }
    end

    def self.non_free_user_plans
      user_plans.reject { |plan| [FREE, ENTERPRISE].include?(plan.name) }
    end

    def self.all_non_free_user_plans
      all_user_plans.reject { |plan| [FREE, ENTERPRISE].include?(plan.name) }
    end

    def self.biggest_user_plan
      user_plans.max_by { |plan| plan.cost } or raise GitHub::Billing::Error, "no plans?"
    end

    def self.biggest_org_plan
      org_plans.max_by { |plan| plan.cost } or raise GitHub::Billing::Error, "no plans?"
    end

    def self.per_seat_plans
      all.select { |plan| plan.per_seat? }
    end

    # Public: the names of all free plans
    def self.free_names
      all.select { |plan| plan.free? }.map(&:name)
    end

    def self.org_plan_for_discount(discount)
      org_plans.reverse.detect { |plan| !plan.enterprise? && plan.cost <= discount }
    end

    def self.user_plan_for_discount(discount)
      user_plans.reverse.detect { |plan| !plan.enterprise? && plan.cost <= discount }
    end

    # Public: all of the available non-enterprise plans.
    #
    # Loads the plans from config/plans.yml and sorts them by cost and name.
    #
    # Returns an Array
    def self.all
      return @all if @all

      plans_file = YAML.safe_load_file(File.join(GitHub::AppEnvironment.root, "config/plans.yml"), aliases: true)


      @all = plans_file["plans"].map do |info|
        next if info["name"] == ENTERPRISE && !GitHub.single_or_multi_tenant_enterprise?
        new(info)
      end.compact.sort
    end

    def self.supported_org_plans_for_feature(feature:, visibilities: [:public, :private])
      visibilities.flat_map do |vis|
        all_org_plans.select { |plan| plan.supports?(feature, visibility: vis) }
      end.uniq
    end

    # Internal: initialize a new Plan
    #
    # options - a Hash of data from the plans.yml file.
    #           name       - required name of a plan
    #           orgs       - whether or not the plan is for orgs, default false
    #           cost       - required cost of the plan in dollars
    #           base_units - number of units included in the cost, if applicable
    #           unit_cost  - cost of additional units, if applicable
    #           coupon     - whether or not this plan is for a coupon, default false
    #           hidden     - whether or not the plan should be hidden, default false
    #           legacy     - whether or not the plan is legacy, default false
    #           features   - a list of features accessible to the plan
    #           limits     - a list of features inaccesssible to the plan
    #           github_actions - various options related to GitHub Actions
    #                            included_minutes - the number of minutes included in the plan
    #                            unit_cost        - the cost of additional minutes used
    #           package_registry - options related to GitHub Package Registry
    #                              included_bandwidth_in_gigabytes - GBs of included data transfer
    #           shared_storage - options related to GitHub Shared Storage
    #                             included_megabytes - the number of free megabytes before overages kick in
    #           codespaces - options related to GitHub Codespaces
    #                             included_compute_minutes - Number of compute usage minutes included
    #                             included_storage_gigabytes - Number of storage usage megabytes
    #           copilot_for_biz - whether GitHub Copilot for Businesses is enabled for this plan
    #           advanced_security - whether GitHub GHAS is enabled for this plan
    #           feature_flag_overrides - A hash containing overrides of default feature definitions
    #                                    based on enrollment in a given feature flag
    #           pro_badge  - whether or not this plan gives users "pro" badges on their profiles
    def initialize(options)
      @options            = options
      @name               = options.fetch("name")
      @orgs               = options.fetch("orgs", false)
      @coupon             = options.fetch("coupon", false)
      @hidden             = options.fetch("hidden", false)
      @legacy             = options.fetch("legacy", false)
      @features           = options.fetch("features", {})
      @limits             = options.fetch("limits", {})
      @trial              = options.fetch("trial", {})
      @github_actions     = options.fetch("github_actions", {})
      @package_registry   = options.fetch("package_registry", {})
      @shared_storage     = options.fetch("shared_storage", {})
      @codespaces         = options.fetch("codespaces", {})
      @copilot_for_biz    = options.fetch("copilot_for_biz", false)
      @advanced_security  = options.fetch("advanced_security", false)
      @rate_plans         = options.fetch("rate_plans", {})
      @pricing_changes    = options.fetch("pricing_changes", {})
      @org_features       = options.fetch("org_features", {})
      @org_limits         = options.fetch("org_limits", {})
      @pro_badge          = options.fetch("pro_badge", false)
      @feature_flag_overrides = options.fetch("feature_flag_overrides", {})
      nil
    end

    def cost
      effective_plan.fetch("cost", nil) || (raise KeyError.new(key: "cost"))
    end

    def yearly_cost
      effective_plan.fetch("yearly_cost", (cost * 12))
    end

    def base_units
      effective_plan.fetch("base_units", 0)
    end

    def unit_cost
      effective_plan.fetch("unit_cost", 0) || (raise KeyError.new(key: "unit_cost"))
    end

    def yearly_unit_cost
      effective_plan.fetch("yearly_unit_cost", (unit_cost * 12))
    end

    # Public: The currently effective plan.
    #
    # effective_at: (Optional) The date the user signed up for the plan.
    # Default now.
    #
    # receipt_effective_on: (Optional) The date the transaction occured, which can be used for historical
    # pricing data. Defaults to now.
    #
    # This is the plan whose date is closest to the effective_at without being
    # in the future
    #
    # Returns the effective plan
    def effective_plan
      if @rate_plans.present?
        options_with_active_pricing_changes.merge(effective_rate_plan)
      else
        options_with_active_pricing_changes
      end
    end

    def effective_rate_plan
      reverse_chronological_rate_plans.detect do |_, rate_plan|
        is_rate_plan_effective?(rate_plan)
      end&.last.to_h
    end

    def is_rate_plan_effective?(rate_plan)
      DateTime.parse(rate_plan["effective_at"]).in_billing_timezone <= effective_at
    end

    def reverse_chronological_rate_plans
      @rate_plans.sort_by do |_, rate_plan|
        rate_plan["effective_at"]
      end.reverse
    end

    def options_with_active_pricing_changes
      @options.dup.tap do |effective_options|
        chronological_pricing_changes.each do |_, pricing_changes|
          effective_options.merge!(pricing_changes) if pricing_changes_enabled?(pricing_changes)
        end
      end
    end

    def pricing_changes_enabled?(pricing_changes)
      change_effective_at = DateTime.parse(pricing_changes["effective_at"]).in_billing_timezone
      receipt_effective_on >= change_effective_at
    end

    def chronological_pricing_changes
      @chronological_pricing_changes ||= @pricing_changes.sort_by { |_, changes| changes["effective_at"] }
    end

    private def receipt_effective_on
      @receipt_effective_on || GitHub::Billing.today
    end

    # Public: Date that the user signed up for the plan.
    #
    # Returns nothing
    def effective_at=(effective_at)
      @effective_at = effective_at
    end

    # Public: DateTime the user signed up for the plan
    #
    # Defaults to current time in the Billing Timezone
    def effective_at
      @effective_at ||= account&.plan_effective_at || GitHub::Billing.now
    end

    def has_business_account_with_trial?
      return false unless account
      account.is_a?(Business) && account.trial? && !account.downgraded_to_free_plan?
    end

    # it would be nice to memoize this, but we can't since it depends on account
    # and the account on the plan object can change after initialization
    def entitlement_plan_name
      if account
        trial = ::Billing::EnterpriseCloudTrial.new(account)
        if (business_plus? && trial.active?) || has_business_account_with_trial?
          return "enterprise_trial"
        end

        if account.is_a?(Business) && account.only_for_copilot?
          return "enterprise_for_copilot"
        end

        if account.is_a?(Business) && account.feature_flag_enabled?(:billing_sales_managed_trial_plan_name, default: false) && business_plus? && account.sales_managed_trial?
          return "enterprise_sales_managed_trial"
        end
      end

      case name
      when BUSINESS_PLUS
        "enterprise"
      when BUSINESS
        "team"
      when PRO
        "pro"
      when FREE, FREE_WITH_ADDONS
        if account
          if account.is_a?(Business)
            "free_organization" # there is no "free_business" plan, they should use the "free_organization" plan
          else
            "free_#{account.class.name.underscore}" # user or organization
          end
        else
          "free_user"
        end
      when EMU_USER
        no_entitlements_change = @pricing_changes.find { |name, _changes| name == "no_entitlements" }&.last
        if pricing_changes_enabled?(no_entitlements_change)
          "emu_user"
        else
          "free_user"
        end
      else
        nil
      end
    end

    def metered_billing_eligible?
      actions_eligible? || package_registry_eligible? || shared_storage_eligible?
    end

    # Public: Returns whether the plan is eligible for shared storage
    def shared_storage_eligible?
      @shared_storage.present?
    end

    private def shared_storage
      effective_plan.fetch("shared_storage", @shared_storage)
    end

    # Public: Returns whether the plan is eligible for codespaces
    def codespaces_eligible?
      @codespaces.present?
    end

    def copilot_for_biz_eligible?
      return false if account&.user?

      @copilot_for_biz.present?
    end

    def advanced_security_eligible?
      @advanced_security.present?
    end

    # Public: Returns whether the plan is eligible for package registry
    def package_registry_eligible?
      @package_registry.present?
    end

    private def package_registry
      effective_plan.fetch("package_registry", @package_registry)
    end

    # Public Returns whether the plan is eligible for actions
    def actions_eligible?
      @github_actions.present?
    end

    def trial_effective_github_actions_included_minutes(effective_at:)
      trial_effective_github_actions_override(effective_at: effective_at).fetch("included_private_minutes", 0)
    end

    # Entitlements access methods:

    # if as_of is left nil, it will default to the current time
    def entitlements
      as_of = receipt_effective_on if receipt_effective_on < GitHub::Billing.today

      if as_of.is_a?(Date)
        as_of = GitHub::Billing.date_in_timezone(as_of).to_time
      end

      @entitlements ||= Hash.new
      return @entitlements[as_of] if @entitlements.keys.include?(as_of)

      plan_name = entitlement_plan_name

      client = ::Billing::Api::ClientWrapper.new # we're not going to send an account to the API call for now

      retrieved_entitlements = if as_of.nil?
        cache_key = "billing:entitlements:v2:#{plan_name}"
        GitHub.cache.fetch(cache_key, { stats_key: cache_key, ttl: 1.day }) do
          response = client.get_entitlement_plans(plan_name: plan_name)
          raise EntitlementError if response.is_a?(::Billing::Api::ClientWrapper::BillingClientError)
          response
        end
      else
        client.get_entitlement_plans(plan_name: plan_name, as_of: as_of)
      end

      raise EntitlementError if retrieved_entitlements.is_a?(::Billing::Api::ClientWrapper::BillingClientError)

      @entitlements[as_of] = retrieved_entitlements[:entitlement_plans].each_with_object({}) do |entitlement_plan, resp_hash|
        resp_hash[entitlement_plan[:name].gsub(/[^0-9A-Za-z]/, "").underscore.to_sym] = {
          name: entitlement_plan[:name],
          quantity: entitlement_plan[:quantity],
          unit_of_measure: entitlement_plan[:unit_of_measure][:name]
        }
      end
    end

    # Public: Returns the number of hours included for Compute usage in codespaces
    def codespaces_included_compute_hours
      if GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:proxia_skip_entitlements_api, default: false)
        0
      else
        entitlements.dig(:codespaces_compute, :quantity) || 0
      end
    end

    # Public: Returns the number of gigabytes included for Storage usage in codespaces
    def codespaces_included_storage_gigabyte_months
      if GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:proxia_skip_entitlements_api, default: false)
        0
      else
        entitlements.dig(:codespaces_storage, :quantity) || 0
      end
    end

    def actions_included_private_minutes
      if entitlement_plan_name.nil?
        github_actions.fetch("included_private_minutes", 0)
      elsif GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:proxia_skip_entitlements_api, default: false)
        # yes, I know the logic is duplicated from the if statement, but I want to keep it seperate until we have Meuse fully removed
        github_actions.fetch("included_private_minutes", 0)
      else
        begin
          entitlements.dig(:actions, :quantity) || 0
        rescue EntitlementError
          GitHub.dogstats.increment("billing.entitlements_api_failover", tags: ["method:actions_included_private_minutes"])
          trial = ::Billing::EnterpriseCloudTrial.new(account)
          if business_plus? && trial.active?
            trial_effective_github_actions_included_minutes(effective_at: trial.started_on)
          elsif has_business_account_with_trial?
            trial_effective_github_actions_included_minutes(effective_at: GitHub::Billing.today)
          else
            github_actions.fetch("included_private_minutes", 0)
          end
        end
      end
    end

    # The method return the entitlement quantity in megabyte-months
    def shared_storage_included_megabytes
      if entitlement_plan_name.nil?
        shared_storage.fetch("included_megabytes", 0)
      elsif GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:proxia_skip_entitlements_api, default: false)
        # yes, I know the logic is duplicated from the if statement, but I want to keep it separate until we have Meuse fully removed
        shared_storage.fetch("included_megabytes", 0)
      else
        begin
          # Meuse returns shared storage entitlements in megabyte-hours
          # so we need to convert it to megabyte-months
          calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new
          quantity = entitlements.dig(:shared_storage, :quantity) || 0
          calculator.monthly_rate_for(units_per_hour: quantity).to_f
        rescue EntitlementError
          GitHub.dogstats.increment("billing.entitlements_api_failover", tags: ["method:shared_storage_included_megabytes"])
          shared_storage.fetch("included_megabytes", 0)
        end
      end
    end

    # Public: Returns the number of gigabytes of data transfer included in the Package Registry for the plan
    def package_registry_included_bandwidth
      if entitlement_plan_name.nil?
        package_registry.fetch("included_bandwidth_in_gigabytes", 0)
      elsif GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:proxia_skip_entitlements_api, default: false)
        # yes, I know the logic is duplicated from the if statement, but I want to keep it separate until we have Meuse fully removed
        package_registry.fetch("included_bandwidth_in_gigabytes", 0)
      else
        begin
          entitlements.dig(:packages, :quantity) || 0
        rescue EntitlementError
          GitHub.dogstats.increment("billing.entitlements_api_failover", tags: ["method:package_registry_included_bandwidth"])
          package_registry.fetch("included_bandwidth_in_gigabytes", 0)
        end
      end
    end

    private def github_actions
      effective_plan.fetch("github_actions", @github_actions)
    end

    private def trial_github_actions
      @trial.fetch("github_actions", @github_actions)
    end

    private def trial_effective_github_actions_override(effective_at:)
      @_trial_overrides ||= trial_github_actions.sort_by { |override| override["effective_at"].to_date }.reverse!

      @_trial_overrides.detect { |override| override["effective_at"].to_date <= effective_at } || github_actions
    end

    # Public: Returns the per-minute unit cost for GitHub Actions in excess of
    # the number of minutes included in the plan
    def actions_overage_unit_cost
      # TODO: this method doesn't really belong here. While Actions V1 pricing was related to the user's plan, V2
      # bases the pricing on the runtime a job was excuted.
      unit_cost = actions_eligible? ? ::Billing::Actions::ZuoraProduct.unit_cost(account: account) : 0
      BigDecimal(unit_cost)
    end

    # Public: Returns the per-minute unit cost in cents for GitHub Actions in excess of
    # the number of minutes included in the plan
    def actions_overage_unit_cost_cents
      # TODO: see actions_overage_unit_cost
      actions_overage_unit_cost * 100
    end

    def display_name(account_type = nil)
      if name == FREE_WITH_ADDONS || (account_type == "Organization" && name == "free")
        "free"
      elsif pro?
        "pro"
      elsif business?
        "team"
      elsif business_plus?
        "enterprise"
      elsif account_type == "Organization" && name == "free"
        "team for open source"
      else
        name
      end
    end

    def titleized_display_name
      display_name.titleize
    end

    # Display name for Salesforce Business Line.
    def business_line
      if business?
        "GitHub Team"
      elsif business_plus?
        "GitHub Enterprise"
      end
    end

    # Public: Does this plan support a gated feature?
    #
    # Note: Please use `User#plan_supports?` and `Repository#plan_supports?` instead
    # of relying directly on this method.
    #
    # feature      - The feature Symbol to check (e.g. :codeowners)
    # visibility   - (Optional) The visibility scope. :public, :private, or :internal.
    # org          - (Optional) Check against any org-specific overrides.
    # feature_flag - (Optional) Look for any overrides for this feature flag name
    sig do
      params(
        feature: Symbol,
        visibility: T.nilable(T.any(Symbol, String)),
        org: T::Boolean,
        feature_flag: T.nilable(T.any(Symbol, String))
      ).returns(T::Boolean)
    end
    def supports?(feature, visibility: nil, org: false, feature_flag: nil)
      handle_unknown_feature!(feature, FEATURES.keys)

      overrides = feature_overrides(org: org, feature_flag: feature_flag)

      if overrides
        override_setting = find_feature_setting(feature, from: overrides, scope: visibility)
        return !!override_setting unless override_setting.nil?
      end

      !!find_feature_setting(feature, from: features, scope: visibility)
    end

    # Public: Integer limit for gated feature.
    #
    # Note: Please use `User#plan_limit` and `Repository#plan_limit` instead
    # of relying directly on this method.
    #
    # feature      - The feature Symbol to check (e.g. :codeowners)
    # visibility   - (Optional) The visibility scope. :public, :private, or :internal.
    # org          - (Optional) Check against any org-specific overrides.
    # feature_flag - (Optional) Look for any overrides for this feature flag name
    #
    # Returns an Integer.
    def limit(feature, visibility: nil, org: false, feature_flag: nil)
      handle_unknown_feature!(feature, LIMITS.keys)

      overrides = limit_overrides(org: org, feature_flag: feature_flag)

      if overrides
        override_setting = find_feature_setting(feature, from: overrides, scope: visibility)
        return override_setting.to_i unless override_setting.nil?
      end

      find_feature_setting(feature, from: limits, scope: visibility).to_i
    end

    private def feature_overrides(feature_flag: nil, org: false)
      feature_flag_name = feature_flag.to_s

      if feature_flag && @feature_flag_overrides[feature_flag_name]
        if org
          @feature_flag_overrides[feature_flag_name]["org_features"] || @org_features
        else
          @feature_flag_overrides[feature_flag_name]["features"]
        end
      elsif org
        @org_features
      end
    end

    private def limit_overrides(feature_flag: nil, org: false)
      feature_flag_name = feature_flag.to_s

      if feature_flag && @feature_flag_overrides[feature_flag_name]
        if org
          @feature_flag_overrides[feature_flag_name]["org_limits"] || @org_limits
        else
          @feature_flag_overrides[feature_flag_name]["limits"]
        end
      elsif org
        @org_limits
      end
    end

    # Internal: Finds the setting that takes precedence from a given settings group.
    #
    # If scope is provided and a setting exists for that specific feature+scope, it will
    # be returned. Otherwise, the unscoped setting will be returned.
    #
    # Examples:
    #
    #   find_feature_setting(:repos, from: { "repos" => true, "repos.private" => false }, scope: :private)
    #   => false
    #   find_feature_setting(:repos, from: { "repos" => true }, scope: :private)
    #   => true
    #   find_feature_setting(:repos, from: { "repos" => true, "repos.private" => false })
    #   => true
    #   find_feature_setting(:unknown, from: { "repos" => true }, scope: :private)
    #   => nil
    #
    # name      - The setting name Symbol to check (e.g. :codeowners)
    # from      - The settings group hash containing the settings.
    # scope     - (Optional) The scope of the setting (e.g. :public, :private, or :internal).
    #
    # Returns the setting value or nil if no setting exists.
    def find_feature_setting(name, from:, scope: nil)
      candidates = [name.to_s]
      candidates.unshift("#{name}.private") if scope&.to_sym == :internal # Internal repos fall back to 'private' feature scope
      candidates.unshift("#{name}.#{scope}") if scope

      from.values_at(*candidates).compact.first
    end

    def handle_unknown_feature!(feature, supported_features)
      raise UnknownFeatureError.new(feature, supported_features) unless supported_features.include?(feature)
    rescue UnknownFeatureError => e
      if GitHub.raise_on_unknown_plan_feature?
        raise e
      else
        Failbot.report(e)
      end
    end

    # Public: Disk space available in bytes.
    # Note: This is only used for the API and basically meaningless. It used to
    # be the amount of space allotted to users with this plan, in bytes. Now we
    # just show the largest number we had in plans.yml.
    #
    # Returns an Integer
    def space
      999_999_999_999
    end

    # Public: Should this plan be visible to everyone? (High-level plans are hidden)
    #
    # Returns a Boolean
    def hidden?
      @hidden
    end

    # Public: Is this plan given out as part of a coupon?
    #
    # These are used for events such as hackathons, rails rumble, etc.
    #
    # Returns a Boolean
    def coupon?
      @coupon
    end

    # Public: Is this a legacy plan? It shouldn't be used for any new customers.
    #
    # Returns a Boolean
    def legacy?
      @legacy
    end

    # Public: Is this plan for individual users or for organizations?
    #
    # Returns a Boolean
    def orgs?
      @orgs
    end

    # Public: Do users with this plan get a pro badge on their profile?
    #
    # Returns a Boolean
    def pro_badge?
      @pro_badge
    end

    # Public: Compare two plans, by cost and then by name.
    #
    # Returns one of -1, 0, 1
    def <=>(other)
      return nil unless other.is_a?(Plan)

      [cost, @name] <=> [other.cost, other.name]
    end

    # Public: The base cost of this plan in cents
    #
    # Returns an Integer
    def cost_in_cents
      cost * 100
    end

    def yearly_cost_in_cents
      yearly_cost * 100
    end

    def org_plan_or_per_seat?
      !coupon? && orgs? && (per_seat? || !hidden?)
    end

    # Public: Is this plan for organizations only?
    #
    # Returns a Boolean
    def org_plan?
      !coupon? && orgs? && !hidden?
    end

    # Public: Is this plan both hidden and for organizations only?
    #
    # Returns a Boolean
    def hidden_org_plan?
      !coupon? && orgs? && hidden?
    end

    # Public: Does the plan have, effectively, unlimited repositories?
    #
    # Returns a Boolean
    def unlimited?(org: false, feature_flag: nil)
      count = org ? org_repos(feature_flag: feature_flag) : repos(feature_flag: feature_flag)
      count >= UNLIMITED_REPOS
    end

    # Number of private repositories this plans allows for users
    # deprecated: use the limit API instead
    def repos(feature_flag: nil)
      limit(:repos, visibility: :private, feature_flag: feature_flag)
    end

    # Number of private repositories this plan allows for orgs
    def org_repos(feature_flag: nil)
      limit(:repos, visibility: :private, org: true, feature_flag: feature_flag)
    end

    # Public: Is the cost of this plan $0? We ignore plans that have a base
    #         cost of $0.
    #
    # Returns a Boolean
    def free?
      if per_seat? || free_with_addons?
        false
      else
        cost.zero?
      end
    end

    # Public: Is this cost of this plan greater than $0?
    #
    # Returns a Boolean
    def paid?
      !free?
    end

    # Public: Is this the free_with_addons plan.
    #
    # Returns a Boolean
    def free_with_addons?
      name == FREE_WITH_ADDONS
    end

    # Public: Is this the enterprise plan?
    #
    # Returns a Boolean
    def enterprise?
      name == ENTERPRISE
    end

    # Public: Is this one of the per seat plans?
    #
    # Returns a Boolean
    def per_seat?
      name == BUSINESS || name == BUSINESS_PLUS
    end

    # Public: Is this one of the per repository plans?
    #
    # Returns a Boolean
    def per_repository?
      !per_seat? && !free_with_addons? && !free? && !pro?
    end

    # Public: Is this the business plan?
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def business?
      name == BUSINESS
    end

    def business_plus?
      name == BUSINESS_PLUS
    end

    # Public: Is this the Pro plan?
    #
    # Returns a Boolean
    def pro?
      name == PRO
    end

    # Public: Is this plan only for Users
    #
    # Returns a Boolean
    def user_plan?
      @name == FREE || (!coupon? && !hidden? && !orgs?)
    end

    # Public: Is this plan only for Organizations
    #
    # Returns a Boolean
    def hidden_user_plan?
      @name == FREE || @name == FREE_WITH_ADDONS || (!coupon? && hidden? && !orgs?)
    end

    # Public: Can this plan be upgraded for more repositories?
    #
    # Returns a Boolean
    def upgradeable?
      if orgs?
        org_repos < Plan.biggest_org_plan.org_repos
      else
        repos < Plan.biggest_user_plan.repos
      end
    end

    # Public: The cost of each additional unit in cents
    #
    # Returns an Integer
    def unit_cost_in_cents
      unit_cost * 100
    end

    def yearly_unit_cost_in_cents
      yearly_unit_cost * 100
    end

    def feature_information
      FEATURE_INFORMATION[@name.to_sym]
    end

    def to_s
      @name
    end

    # legacy plans needed for test:
    def self.micro
      find!("micro")
    end

    def self.bronze
      find!("bronze")
    end

    def self.silver
      find!("silver")
    end

    def self.gold
      find!("gold")
    end

    def self.small
      find!("small")
    end

    def self.medium
      find!("medium")
    end

    def self.large
      find!("large")
    end

    def self.curium
      find!("curium")
    end

    def self.platinum
      find!("platinum")
    end

    def self.diamond
      find!("diamond")
    end

    def self.aluminium
      find!("aluminium")
    end
  end
end
