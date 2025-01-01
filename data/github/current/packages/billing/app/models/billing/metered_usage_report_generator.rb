# typed: strict
# frozen_string_literal: true

class Billing::MeteredUsageReportGenerator
  extend T::Sig
  include GitHub::Memoizer

  HEADER = T.let(["Date", "Product", "SKU", "Quantity", "Unit Type", "Price Per Unit ($)", "Multiplier", "Owner", "Repository Slug", "Username", "Actions Workflow", "Notes"], T::Array[String])
  VALID_DURATIONS = T.let([7, 30, 90, 180].freeze, T::Array[Integer])
  VALID_PRODUCTS = T.let(%w[all actions packages shared_storage codespaces copilot_for_business ghec].freeze, T::Array[String])
  WORKFLOW_BATCH_SIZE = T.let(1000, Integer)

  sig { params(owner: Billing::Types::Account, days: Integer, requester: T.nilable(User), products: T::Array[String]).returns(String) }
  def self.csv_for(owner:, days:, requester: nil, products: ["all"])
    new(owner, start_date: GitHub::Billing.today - days.days, end_date: GitHub::Billing.today, requester: requester, products: products).to_csv
  end

  sig do
    params(
      billable_owner: Billing::Types::Account,
      start_date: UsageDate,
      end_date: UsageDate,
      requester: T.nilable(User),
      products: T::Array[String]
    ).void
  end
  def initialize(billable_owner, start_date:, end_date: GitHub::Billing.today, requester: nil, products: ["all"])
    @billable_owner = billable_owner
    @start_date = start_date
    @end_date = end_date
    @requester = requester
    @products = products

    raise ArgumentError, "Invalid products: #{products}" unless (products - VALID_PRODUCTS).empty?
  end

  sig { returns(String) }
  def to_csv
    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:all"]) do
      CSV.generate do |csv|
        csv << HEADER

        ActiveRecord::Base.connected_to(role: :reading) do
          (start_date..end_date).each_slice(batch_size) do |date_range|
            usages = usage_between(start_date: T.must(date_range.first), end_date: T.must(date_range.last))
            repositories = Repository
              .where(id: usages.map(&:repository_id))
              .includes(:owner)
              .select(:id, :name, :owner_id, :owner_login)
              .index_by(&:id)

            usages.each do |usage|
              csv << usage.to_row(repositories)
            end
          end
        end
      end
    end
  end

  sig { params(requester: User, target: Billing::Types::Account).returns(T.nilable(String)) }
  def self.email_for_export(requester:, target:)
    if target.user? || requester.is_enterprise_managed? || (requester.site_admin? && !T.cast(target, T.any(Organization, Business)).direct_or_team_member?(requester))
      return requester.default_notification_email
    end

    email_org =
      if target.is_a?(Business)
        target.organizations.first
      else
        target = T.cast(target, Organization)
      end

    if email_org.present? && target.restrict_notifications_to_verified_domains?
      email_org.notifiable_emails_for(requester).first&.email
    else
      GitHub.newsies.email(requester, email_org).value
    end
  end

  private

  UsageDate = T.type_alias { T.any(Date, Time, DateTime, ActiveSupport::TimeWithZone) }

  sig { returns(Billing::Types::Account) }
  attr_reader :billable_owner
  sig { returns(UsageDate) }
  attr_reader :start_date
  sig { returns(UsageDate) }
  attr_reader :end_date

  sig { returns(Integer) }
  memoize def batch_size
    if billable_owner.is_organization_billed_through_business?
      2
    else
      8
    end
  end

  sig { params(start_date: UsageDate, end_date: UsageDate).returns(T::Array[Usage]) }
  def usage_between(start_date:, end_date:)
    start_time = T.let(T.unsafe(convert_to_billed_timezone(start_date)).beginning_of_day, ActiveSupport::TimeWithZone)
    end_time = T.let(T.unsafe(convert_to_billed_timezone(end_date)).end_of_day, ActiveSupport::TimeWithZone)

    usages = []
    usages += actions_usages(start_time: start_time, end_time: end_time) if (%w[all actions] & @products).any?
    usages += packages_usage(start_time: start_time, end_time: end_time) if (%w[all packages] & @products).any?
    usages += shared_storage_usage(start_time: start_time, end_time: end_time) if (%w[all shared_storage] & @products).any?
    usages += codespaces_usage(start_time: start_time, end_time: end_time) if (%w[all codespaces] & @products).any?
    usages += copilot_for_business_usage(start_time: start_time, end_time: end_time) if (%w[all copilot_for_business] & @products).any?
    usages += ghec_usage(start_time: start_time, end_time: end_time) if (%w[all ghec] & @products).any?
    usages.sort
  end

  sig { params(date_to_convert: UsageDate).returns(ActiveSupport::TimeWithZone) }
  def convert_to_billed_timezone(date_to_convert)
    # By default, the start and end times are in UTC
    # Customers are billed through Azure using UTC
    if ownership_condition[:billable_owner].billed_through_azure_subscription?
      ActiveSupport::TimeZone["UTC"].parse(date_to_convert.to_s)
    else
      # For now, the only other possibility if not billed through an Azure subscription is Zuora
      # Customers are billed through Zuora using Pacific time
      GitHub::Billing.timezone.parse(date_to_convert.to_s)
    end
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def actions_usages(start_time:, end_time:)
    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:actions"]) do
      lines_with_quantity = {}

      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      line_items = response.map { |line_item| Billing::Actions::UsageLineItemWrapper.new(line_item) }
      grouped_line_items = line_items.group_by do |line_item|
        [line_item.repository_id, convert_to_billed_timezone(line_item.end_time).to_date, line_item.job_runtime_environment, line_item.rate_plan_unit_price, line_item.multiplier, line_item.workflow_id, line_item.actor_id, line_item.sku_diplay_name, line_item.owner_id]
      end

      line_items_sorted_by_end_time = grouped_line_items.sort_by do |(_repo_id, end_timestamp, _runtime_env, _price, _multiplier, _workflow_id, _actor_id, _sku, _owner_id), _line_items|
        end_timestamp
      end

      line_items_sorted_by_end_time.each do |line_item_properties, line_items|
        lines_with_quantity[line_item_properties] = line_items.sum { |line_item| line_item.duration_in_minutes }
      end

      workflow_ids_by_repository_id = Hash.new { |hash, key| hash[key] = Set.new }
      actor_and_owner_ids = Set.new
      lines_with_quantity.each_key do |(repository_id, _date, _runtime, _price, _multiplier, workflow_id, actor_id, _sku, owner_id)|
        workflow_ids_by_repository_id[repository_id] << workflow_id if workflow_id
        actor_and_owner_ids << actor_id if actor_id
        actor_and_owner_ids << owner_id if owner_id
      end



      workflows = T.let({}, T.untyped)
      if @billable_owner.feature_enabled?(:actions_usage_report_batch_workflow_query)
        workflow_ids_by_repository_id.keys.each_slice(WORKFLOW_BATCH_SIZE).each do |workflow_repository_ids|
          # using `T.unsafe` here because Sorbet doesn't have great support for splats right now
          # https://sorbet.org/docs/error-reference#7019
          workflow_ids_by_repository_id_batch = T.unsafe(workflow_ids_by_repository_id).slice(*workflow_repository_ids)

          batch_workflows = workflow_ids_by_repository_id_batch.reduce(Actions::Workflow.none) do |scope, (repository_id, workflow_ids)|
            scope.or(Actions::Workflow.where(repository_id: repository_id, id: workflow_ids))
          end.where(repository_id: workflow_repository_ids).index_by(&:id)
          workflows.merge!(batch_workflows)
        end
      else
        workflows = workflow_ids_by_repository_id.reduce(Actions::Workflow.none) do |scope, (repository_id, workflow_ids)|
          scope.or(Actions::Workflow.where(repository_id: repository_id, id: workflow_ids))
        end.where(repository_id: workflow_ids_by_repository_id.keys).index_by(&:id)
      end

      user_logins = User.where(id: actor_and_owner_ids).pluck(:id, :login).to_h

      lines_with_quantity.map do |(repository_id, date, _runtime, price, multiplier, workflow_id, actor_id, sku, owner_id), value|
        price_per_unit = (multiplier * price.to_d).round(3, :truncate)
        workflow_file = workflows[workflow_id]&.path

        Usage.new(
          billable_owner: billable_owner,
          date: date,
          product: "Actions",
          sku: sku,
          quantity: value.round,
          unit_type: "minute",
          price_per_unit: price_per_unit,
          multiplier: multiplier,
          owner: (owner_id ? user_logins[owner_id] : nil),
          repository_id: repository_id,
          username: (actor_id ? user_logins[actor_id] : nil),
          workflow_file: workflow_file,
          requester: @requester
        )
      end
    end
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def packages_usage(start_time:, end_time:)
    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:packages"]) do
      lines_with_quantity = {}

      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:packages],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      line_items = response.map { |line_item| Billing::PackageRegistry::UsageLineItemWrapper.new(line_item) }
      grouped_line_items = line_items.group_by do |line_item|
        [line_item.registry_package_id, convert_to_billed_timezone(line_item.downloaded_at).to_date, line_item.rate_plan_unit_price, line_item.multiplier, line_item.actor_id, line_item.sku_display_name, line_item.owner_id]
      end

      line_items_sorted_by_downloaded_at = grouped_line_items.sort_by do |(_registry_package_id, downloaded_at, _price, _multiplier, _actor_id, _sku, _owner_id), _line_items|
        downloaded_at
      end

      line_items_sorted_by_downloaded_at.each do |line_item_properties, line_items|
        lines_with_quantity[line_item_properties] = line_items.sum { |line_item| line_item.size_in_bytes }
      end

      # avoid n+1 in `.map` below by associating packages with repository_id's
      package_ids = Set.new
      actor_and_owner_ids = Set.new
      lines_with_quantity.each_key do |(registry_package_id, _downloaded_at, _price, _multiplier, actor_id, _sku, owner_id)|
        package_ids << registry_package_id
        actor_and_owner_ids << actor_id if actor_id
        actor_and_owner_ids << owner_id if owner_id
      end

      packages_repo_id = Registry::Package.where(id: package_ids).pluck(:id, :repository_id).to_h
      users_login = User.where(id: actor_and_owner_ids).pluck(:id, :login).to_h

      usages = lines_with_quantity.map do |(registry_package_id, date, price, multiplier, actor_id, sku, owner_id), value|
        price_per_unit = multiplier * price

        Usage.new(
          billable_owner: billable_owner,
          date: date,
          product: "Packages",
          sku: sku,
          quantity: (value.to_f / 1.gigabyte).round(4),
          unit_type: "gb",
          price_per_unit: "%.2f" % price_per_unit,
          multiplier: multiplier,
          owner: (owner_id ? users_login[owner_id] : nil),
          repository_id: packages_repo_id[registry_package_id],
          username: (actor_id ? users_login[actor_id] : nil),
          requester: @requester
        )
      end

      usages.group_by { |usage| [usage.repository_id, usage.date, usage.price_per_unit, usage.multiplier, usage.username, usage.sku] }.values.map do |usages|
        usages.reduce(&:+)
      end
    end
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def shared_storage_usage(start_time:, end_time:)
    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:shared_storage"]) do
      line_items = {}

      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:shared_storage],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      line_items = response.map { |line_item| Billing::SharedStorage::UsageLineItemWrapper.new(line_item) }
      grouped_repo_id_usage_at_line_items = line_items.group_by do |line_item|
        [line_item.repository_id, convert_to_billed_timezone(line_item.aggregate_effective_at).to_date, line_item.multiplier, line_item.rate_plan_unit_price, line_item.actor_id, line_item.sku_display_name, line_item.owner_id]
      end

      line_items = grouped_repo_id_usage_at_line_items.map do |(repository_id, effective_at, multiplier, rate_plan_unit_price, actor_id, sku, owner_id), line_items|
        total_byte_hours = line_items.sum { |line_item| line_item.size_in_bytes }
        total_byte_days = total_byte_hours / 1.day.in_hours

        [repository_id, effective_at, total_byte_days, multiplier, rate_plan_unit_price, actor_id, sku, owner_id]
      end

      actor_and_owner_ids = Set.new
      line_items.each do |(_repository_id, _date, _quantity, _multiplier, _unit_price, actor_id, _sku, owner_id)|
        actor_and_owner_ids << actor_id if actor_id
        actor_and_owner_ids << owner_id if owner_id
      end

      users_login = User.where(id: actor_and_owner_ids).pluck(:id, :login).to_h

      line_items.map do |(repository_id, date, value, multiplier, price_per_mb_hour, actor_id, sku, owner_id)|
        price_per_mb_day = (price_per_mb_hour * 1.day.in_hours)
        gb_in_mbs = 1.gigabyte / 1.megabyte
        price_per_gb_day = (price_per_mb_day * gb_in_mbs).round(3)

        Usage.new(
          billable_owner: billable_owner,
          date: date,
          product: "Shared Storage",
          sku: sku,
          quantity: (value.to_f / 1.gigabyte).round(4),
          unit_type: "gb-day",
          price_per_unit: price_per_gb_day,
          multiplier: multiplier,
          owner: (owner_id ? users_login[owner_id] : nil),
          repository_id: repository_id,
          username: (actor_id ? users_login[actor_id] : nil),
          requester: @requester
        )
      end
    end
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def codespaces_usage(start_time:, end_time:)

    codespaces_usage = GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:codespaces"]) do
      actor_and_owner_ids = Set.new
      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:codespaces],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      line_items = response.map do |line_item|
        actor_and_owner_ids << line_item.actor_id if line_item.actor_id
        actor_and_owner_ids << line_item.owner_id if line_item.owner_id

        Billing::Codespaces::UsageLineItemWrapper.new(line_item)
      end

      users_login = User.where(id: actor_and_owner_ids).pluck(:id, :login).to_h

      line_items.map do |line_item|
        Usage.new(
          billable_owner: billable_owner,
          date: convert_to_billed_timezone(line_item.end_time).to_date,
          product: "Codespaces - Linux",
          sku: line_item.sku_display_name,
          quantity: line_item.usage.round(4),
          unit_type: line_item.unit_type,
          price_per_unit: line_item.rate_plan_unit_price,
          multiplier: line_item.multiplier,
          owner: (line_item.owner_id ? users_login[line_item.owner_id] : nil),
          repository_id: line_item.repository_id,
          username: (line_item.actor_id ? users_login[line_item.actor_id] : nil),
          workflow_file: line_item.action_workflow_name,
          requester: @requester
        )
      end
    end

    grouped_codespaces_usage = codespaces_usage.group_by do |usage|
      [usage.repository_id, usage.date, usage.sku, usage.username, usage.multiplier, usage.price_per_unit]
    end

    grouped_codespaces_usage.values.map do |usages|
      usages.reduce(&:+)
    end.sort_by(&:date)
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def copilot_for_business_usage(start_time:, end_time:)
    return [] unless copilot_for_business_enabled?(@billable_owner)

    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:copilot"]) do
      actor_and_owner_ids = Set.new
      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      line_items = response.map do |line_item|
        actor_and_owner_ids << line_item.actor_id if line_item.actor_id
        actor_and_owner_ids << line_item.owner_id if line_item.owner_id

        Billing::Copilot::UsageLineItemWrapper.new(line_item)
      end

      users_login = User.where(id: actor_and_owner_ids).pluck(:id, :login).to_h

      line_items.map do |line_item|
        Usage.new(
          billable_owner: billable_owner,
          date: convert_to_billed_timezone(line_item.end_time).to_date,
          product: "Copilot",
          sku: line_item.sku_display_name,
          quantity: line_item.usage.round(4),
          unit_type: "user-month",
          price_per_unit: line_item.rate_plan_unit_price,
          multiplier: line_item.multiplier,
          owner: (line_item.owner_id ? users_login[line_item.owner_id] : nil),
          repository_id: line_item.repository_id,
          username: (line_item.actor_id ? users_login[line_item.actor_id] : nil),
          requester: @requester
        )
      end
    end
  end

  sig { params(start_time: UsageDate, end_time: UsageDate).returns(T::Array[Usage]) }
  def ghec_usage(start_time:, end_time:)
    return [] unless @billable_owner.is_a?(Business) && @billable_owner.metered_ghe?

    GitHub.dogstats.distribution_time("billing.usage_report", tags: ["product:ghec"]) do
      response = billing_api_client.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:ghec],
        usage_starts_at: start_time,
        usage_ends_at: end_time,
        additional_retries: true,
        per_page: 200
      )
      raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

      usage = response.map do |line_item|
        Billing::BaseUsageLineItemWrapper.new(line_item)
      end

      usage.map do |line_item|
        Usage.new(
          billable_owner: billable_owner,
          date: convert_to_billed_timezone(line_item.usage_at.to_time.utc).to_date,
          product: "GHEC",
          sku: line_item.sku_name.titleize,
          quantity: line_item.quantity.round(4),
          unit_type: "user-month",
          price_per_unit: line_item.rate_plan_unit_price,
          multiplier: line_item.multiplier,
          repository_id: nil,
          requester: @requester
        )
      end
    end
  end

  sig { returns(::Billing::Api::ClientWrapper) }
  memoize def billing_api_client
    ::Billing::Api::ClientWrapper.new(
      billable_owner: ownership_condition[:billable_owner],
      owner: ownership_condition[:owner],
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def ownership_condition
    billable_owner = self.billable_owner
    if billable_owner.is_organization_billed_through_business?
      {
        billable_owner: T.cast(billable_owner, Organization).business,
        owner: billable_owner,
      }
    else
      {
        billable_owner: billable_owner,
      }
    end
  end

  sig { params(account: Billing::Types::Account).returns(T::Boolean) }
  def copilot_for_business_enabled?(account)
    return false unless GitHub.copilot_for_business_enabled?
    return false unless Copilot.copilot_object(account).copilot_for_business_enabled?
    return false unless account.plan.copilot_for_biz_eligible?

    true
  end

  class Usage
    extend T::Sig
    include Comparable

    sig { returns(Date) }
    attr_reader :date
    sig { returns(T.nilable(Integer)) }
    attr_reader :repository_id
    sig { returns(T.nilable(String)) }
    attr_reader :sku
    sig { returns(T.nilable(String)) }
    attr_reader :username
    sig { returns(T.nilable(Numeric)) }
    attr_reader :multiplier
    sig { returns(T.nilable(T.any(String, Numeric))) }
    attr_reader :price_per_unit

    sig do
      params(
        billable_owner: Billing::Types::Account,
        date: Date,
        product: String,
        quantity: T.nilable(Numeric),
        repository_id: T.nilable(Integer),
        sku: T.nilable(String),
        unit_type: T.nilable(String),
        price_per_unit: T.nilable(T.any(String, Numeric)),
        multiplier: T.nilable(Numeric),
        owner: T.nilable(String),
        username: T.nilable(String),
        workflow_file: T.nilable(String),
        requester: T.nilable(User)
      ).void
    end
    def initialize(billable_owner:, date:, product:, quantity:, repository_id:, sku: nil, unit_type: nil, price_per_unit: nil, multiplier: nil, owner: nil, username: nil, workflow_file: nil, requester: nil)
      @billable_owner = billable_owner
      @date = date
      @product = product
      @sku = sku
      @quantity = quantity
      @unit_type = unit_type
      @price_per_unit = price_per_unit
      @multiplier = multiplier
      @owner = owner
      @repository_id = repository_id
      @username = username
      @workflow_file = workflow_file
      @requester = requester
    end

    sig { params(other: Usage).returns(T.self_type) }
    def +(other)
      @quantity = (T.must(quantity) + T.must(other.quantity)).round(4)
      self
    end

    # We want to give first party integrators a nice, polished billing presentation.
    sig { returns(T.nilable(String)) }
    def workflow_file_billing_format
      workflow_file = self.workflow_file
      return workflow_file unless workflow_file&.start_with?(Actions::Workflow::DYNAMIC_BASE_PATH)
      _, integration, slug = workflow_file.split("/")

      integration = T.must(integration)
      slug = T.must(slug)

      if slug.include?(integration)
        "#{slug.titleize}"
      else
        "#{integration.titleize} - #{slug.titleize}"
      end
    end

    sig { params(repository_cache: T::Hash[Integer, Repository]).returns(T::Array[T.untyped]) }
    def to_row(repository_cache)
      repository_id = self.repository_id
      repository_name = (repository_id && repository_cache[repository_id]&.name) || "deleted repositories"
      repository_name = nil if product.to_s.downcase.in?(%w[copilot ghec]) # usage that is not associated with a repository

      if repository_id.nil? && ["packages", "shared storage"].include?(product.downcase)
        # generate a row to show usage by the v2 package registry (ghcr & npm)
        repository_name = "Organization Packages - Data Transfer Out" if product.downcase == "packages"
        repository_name = "Organization Packages" if product.downcase == "shared storage"

        if @billable_owner.is_organization_billed_through_business?
          billable_owner = T.cast(@billable_owner, Organization)
          # nil out everything but "Notes" which says which business is being billed for CR
          @sku = nil
          @quantity = nil
          @unit_type = nil
          @price_per_unit = nil
          @multiplier = nil
          @owner = nil
          @username = nil
          notes = "Included in '#{billable_owner.business&.name}' usage"
        end
      end

      [date.iso8601, product, sku, quantity, unit_type, price_per_unit, multiplier, owner, repository_name, username, workflow_file_billing_format, notes]
    end

    sig { params(other: Usage).returns(T.nilable(Integer)) }
    def <=>(other)
      date <=> other.date
    end

    protected

    sig { returns(String) }
    attr_reader :product
    sig { returns(T.nilable(Numeric)) }
    attr_reader :quantity
    sig { returns(T.nilable(String)) }
    attr_reader :unit_type
    sig { returns(T.nilable(String)) }
    attr_reader :owner
    sig { returns(T.nilable(String)) }
    attr_reader :workflow_file
  end
  private_constant :Usage
end
