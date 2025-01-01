# typed: strict
# frozen_string_literal: true

require "github/ds_extensions"
require "turboghas"

class AdvancedSecurityLicense
  include GitHub::Memoizer

  class TurboghasError < StandardError; end

  sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
  attr_reader :billable_entity

  USER_BATCH_SIZE = 1000

  sig { params(owner: Billing::Types::Account, sku: GitHub::Turboghas::SKU).void }
  def initialize(owner, sku: GitHub::Turboghas::SKU::Bundled) # todo: remove default
    @sku = T.let(sku, GitHub::Turboghas::SKU)
    @entity = owner
    @billable_entity = T.let(self.class.billable_entity(owner), T.nilable(Billing::Types::OrgOrBusiness))
  end

  # Public: Returns the billable entity of the provided User, Organization, or
  # Business.
  #
  # The billable entity is either an Organization or a Business, depending on
  # which license has been purchased. On GHES this is always the global
  # business, but on dotcom if a business license has been purchased, it
  # overrides any org-level license.
  #
  # Can also be nil on dotcom if entity is anything other than an Organization
  # or a Business, and an AdvancedSecurityLicense with a nil billable_entity
  # behaves as if no license has been purchased.
  #

  sig do
    params(
      entity: Billing::Types::Account,
    ).returns(T.nilable(Billing::Types::OrgOrBusiness))
  end
  def self.billable_entity(entity)
    if GitHub.enterprise?
      GitHub.global_business
    # default to tracking at the business level unless the organization has explicitly purchased advanced security
    elsif entity.is_a?(Organization) && entity.delegate_billing_to_business? && (entity.business&.advanced_security_purchased_for_entity? || !entity.advanced_security_purchased_for_entity?)
      entity.business
    elsif entity.is_a?(Organization) || entity.is_a?(Business)
      entity
    elsif entity.is_a?(User)
      ::AdvancedSecurity::Features::User::AdvancedSecurity.new(entity).get_business
    end
  end

  sig do
    params(
      entity: Billing::Types::Account,
      sku: GitHub::Turboghas::SKU,
      repository_ids: T.nilable(T::Array[Integer]),
    ).returns(::Turboghas::Proto::GetSummaryResponse)
  end
  def self.summary(entity:, sku:, repository_ids: nil)
    entity_type = GitHub::Turboghas.entity_type_for(entity)
    customer_id = entity.customer&.id if !entity.is_a?(User) && entity.advanced_security_metered_for_entity?
    additional_user_ids = entity.advanced_security_business_user_ids(sku:) if entity.is_a?(Business)

    response = GitHub::Turboghas.client.get_summary(
      entity_id: entity.id,
      entity_type:,
      repository_ids:,
      customer_id:,
      additional_user_ids:,
      **sku.to_proto,
    )
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?
    response.data.tap do |data|
      # if the customer is bundled we leave these values alone so the ghas chatop command can show speculative figures
      unless (entity.advanced_security_products_bundled? && entity.advanced_security_license.purchased?) || entity.advanced_security_license_for_sku(sku:).purchased?
        data.active_committers = 0
        data.additional_metered_committers = 0
      end
    end
  end

  # TODO: remove all uses of this method for SKU split
  sig do
    params(
      owner: Billing::Types::Account,
    ).returns(Integer)
  end
  def self.seat_usage_increase_if_advanced_security_enabled_for_all_repos(owner:)
    return 0 if owner.nil?
    owner.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).entity_summary.additional_committers
  end

  # Calculates how many extra GHAS seats would be used / contributors would be billed for if
  # GHAS were to be enabled on the given repository.
  #
  # Returns 0 if GHAS is not purchased or is already enabled for the repository.
  # TODO: remove all uses of this method for SKU split
  sig do
    params(
      repo: Repository,
    ).returns(Integer)
  end
  def self.seat_usage_increase_if_advanced_security_enabled_for_repo(repo)
    owner = repo.owner
    # Pass the organization that is paying for the seat which may not always be the owning entity
    billable_entity = AdvancedSecurityLicense.billable_entity(T.must(repo.owner))
    repo_id = repo.id
    return 0 if owner.nil? || repo_id.nil? || !owner.advanced_security_purchased? || repo.advanced_security_enabled?

    seat_usage_increase_if_advanced_security_enabled_for_repos(owner: T.must(billable_entity), repo_ids: [repo_id])
  end

  sig do
    params(
      owner: Billing::Types::Account,
      repo_ids: T.nilable(T::Array[Integer]),
      sku: GitHub::Turboghas::SKU,
    ).returns(Integer)
  end
  def self.seat_usage_increase_if_advanced_security_enabled_for_repos(owner:, repo_ids:, sku: GitHub::Turboghas::SKU::Bundled)
    return 0 if owner.nil?
    # if the caller deliberately passes in an empty list then return zero
    # if they pass in nil, return the full user count
    return 0 if repo_ids.try(:empty?)

    AdvancedSecurityLicense.summary(entity: owner, repository_ids: repo_ids, sku:).additional_committers
  end

  sig { returns(Integer) }
  def seat_usage_increase_if_enabled_for_all_repos
    summary.additional_committers
  end

  sig { returns(Integer) }
  def seat_usage_increase_if_advanced_security_enabled_for_all_repos; seat_usage_increase_if_enabled_for_all_repos; end

  sig { params(repo: Repository).returns(Integer) }
  def seat_usage_increase_if_enabled_for_repo(repo)
    return 0 unless purchased?

    seat_usage_increase_if_enabled_for_repos([repo.id])
  end

  sig { params(repo_ids: T.nilable(T::Array[Integer])).returns(Integer) }
  def seat_usage_increase_if_enabled_for_repos(repo_ids)
    # if the caller deliberately passes in an empty list then return zero
    # if they pass in nil, return the full user count
    return 0 if @billable_entity.nil?
    return 0 if repo_ids.try(:empty?)
    return seat_usage_increase_if_enabled_for_all_repos if repo_ids.nil?
    AdvancedSecurityLicense.summary(entity: @billable_entity, repository_ids: repo_ids, sku: @sku).additional_committers
  end

  sig { params(repo_ids: T.nilable(T::Array[Integer])).returns(Integer) }
  def seat_usage_increase_if_advanced_security_enabled_for_repos(repo_ids)
    seat_usage_increase_if_enabled_for_repos(repo_ids)
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  def enabling_repo_exceeds_seat_allowance?(repo)
    return false unless purchased?
    return false if unlimited_seats?

    seat_usage_increase_if_enabled_for_repos([repo.id]) > remaining_seats
  end

  sig { returns(T::Boolean) }
  def purchased?
    return false if @billable_entity.nil?
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      @billable_entity.advanced_security_purchased?
    when GitHub::Turboghas::SKU::CodeSecurity
      @billable_entity.code_security_purchased?
    when GitHub::Turboghas::SKU::SecretSecurity
      @billable_entity.secret_protection_purchased?
    end
  end

  sig { returns(T::Boolean) }
  def enabling_for_all_repos_would_exceed_seat_allowance?
    return false unless purchased?
    return false if unlimited_seats?
    return false if @billable_entity.nil?

    tags = if @billable_entity.is_a?(Business)
      {
        "gh.business.id" => @billable_entity.id,
        "gh.business.name" => @billable_entity.slug
      }
    else
      {
        "gh.org.id" => @billable_entity.id,
        "gh.org.login" => @billable_entity.display_login
      }
    end

    if allowance_exceeded?
      GitHub.logger.info(
        "Enable all seat allowance already exceeded",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        **tags,
      )

      return true
    end

    would_exceed_seat_allowance = seat_usage_increase_if_enabled_for_all_repos > remaining_seats
    if would_exceed_seat_allowance
      GitHub.logger.info(
        "Enable all will exceed seat allowance",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        **tags,
      )
    end

    would_exceed_seat_allowance
  end

  # Public: Returns the number of seats purchased for use with Advanced Security.
  #
  # On GHES, this can be found by looking at the license file.
  # On Cloud:
  # * return 0 if GHAS is not purchased with a license
  # * for a business-level license delegate to the business-level config
  # * for an "independent" org, check the org-level config
  #
  sig { returns(Integer) }
  def seats
    # This covers users on dotcom since, unlike orgs or businesses, they can't purchase GHAS seats.
    return 0 if @billable_entity.nil?
    return 0 unless purchased?
    if GitHub.enterprise?
      return (
        case @sku
        when GitHub::Turboghas::SKU::Bundled
          GitHub::Enterprise.license.advanced_security_seats
        when GitHub::Turboghas::SKU::CodeSecurity
          GitHub::Enterprise.license.code_security_licenses
        when GitHub::Turboghas::SKU::SecretSecurity
          GitHub::Enterprise.license.secret_protection_licenses
        end
      )
    end
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      @billable_entity.advanced_security_seats_for_entity
    when GitHub::Turboghas::SKU::CodeSecurity
      # For Code Security trials, we return 0 (meaning "unlimited") so that the user can play with
      # a volume purchase without any limits.
      if @entity.is_a?(Business)
        return 0 if ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: @entity).enabled?
      end
      @billable_entity.code_security_license_count
    when GitHub::Turboghas::SKU::SecretSecurity
      # For Secret Protection trials, we return 0 (meaning "unlimited") so that the user can play with
      # a volume purchase without any limits.
      if @entity.is_a?(Business)
        return 0 if ::EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @entity).enabled?
      end
      @billable_entity.secret_scanning_license_count
    end
  end

  # Public: Has GHAS been purchased with unlimited seats?
  sig { returns(T::Boolean) }
  memoize def unlimited_seats?
    return false if @billable_entity.nil?
    if @sku == GitHub::Turboghas::SKU::Bundled
      if @billable_entity.advanced_security_seats_stored_on_subscription_item?
        return @billable_entity.has_active_advanced_security_trial? || false
      end
    end
    (purchased? || false) && seats == 0
  end

  # Public: Has GHAS been enabled via a sales-led trial?
  sig { returns(T::Boolean) }
  def has_sales_serve_trial?
    return false unless @sku == GitHub::Turboghas::SKU::Bundled
    return false if @billable_entity.nil?
    return false if @billable_entity.advanced_security_seats_stored_on_subscription_item?
    @billable_entity.advanced_security_purchased_for_entity? && seats == 0
  end

  # Public: Returns the unique number of users that have contributed to a
  # repository under this org/business with advanced security enabled.
  #
  # Returns an Integer.
  sig { returns(Integer) }
  memoize def consumed_seats
    return 0 if @billable_entity.nil?
    return 0 unless purchased?
    summary.active_committers
  end

  sig { returns(Integer) }
  def seats_used; consumed_seats; end

  sig { returns(Integer) }
  def additional_metered_committers_used; additional_metered_seats; end

  sig { returns(Integer) }
  memoize def additional_metered_seats
    return 0 if GitHub.enterprise?
    return 0 if @billable_entity.nil?
    return 0 unless purchased?
    summary.additional_metered_committers
  end

  sig { returns(::Turboghas::Proto::GetSummaryResponse) }
  memoize def summary
    return ::Turboghas::Proto::GetSummaryResponse.new if @billable_entity.nil?
    AdvancedSecurityLicense.summary(entity: @billable_entity, sku: @sku)
  end

  # provides a summary at the organization level if necessary
  sig { returns(::Turboghas::Proto::GetSummaryResponse) }
  memoize def entity_summary
    return summary if @billable_entity == @entity
    AdvancedSecurityLicense.summary(entity: @entity, sku: @sku)
  end

  # Public: Are more Advanced Security seats being used than have been purchased?
  sig { returns(T::Boolean) }
  def allowance_exceeded?
    return false unless purchased?
    return false if unlimited_seats?
    consumed_seats > seats
  end

  # Public: Returns the number of advanced security seats currently unused.
  #
  # Returns an Integer.
  sig { returns(Integer) }
  memoize def remaining_seats
    # Just make sure we don't return nonsensical negative answers
    [0, seats - consumed_seats].max
  end

  # Returns the complete set of user IDs associated with the billable entity of
  # the license, as defined to qualify for paying for a seat.
  sig { returns(T::Array[Integer]) }
  memoize def user_ids
    # FORCE INDEX(PRIMARY) fixes a potential case where this query executes
    # slowly. See https://github.com/github/code-scanning/issues/2969
    if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
      user_query = User\
      .from("users FORCE INDEX(PRIMARY)")
      .left_joins(:customer)
      .where(type: User, suspended_at: nil)
      .where(customers: { locked_at: nil })
    else
      user_query = User.from("users FORCE INDEX(PRIMARY)").where(type: User, suspended_at: nil, disabled: false)
    end

    return user_query.pluck(:id) - [User.ghost.id] if GitHub.enterprise?

    if @billable_entity.is_a?(Business)
      Business::LicenseAttributer.new(@billable_entity).user_ids
    elsif @billable_entity.is_a?(Organization)
      Organization::LicenseAttributer.new(@billable_entity).user_ids
    else
      return []
    end.to_a.in_groups_of(5000).flat_map do |chunk|
      user_query.where(id: chunk).pluck(:id)
    end
  end

  class GHESCommitters < T::Struct
    const :user_ids, T::Array[Integer]
    const :unmatched, T::Array[Integer]

    sig { returns(T::Array[Integer]) }
    def all
      user_ids + unmatched
    end
  end

  sig { returns(T.nilable(GHESCommitters)) }
  memoize def ghes_committers
    return nil if @billable_entity.nil?

    # group by user_id as it is not a unique column
    rows = @billable_entity.advanced_security_business_user_accounts(sku: @sku).pluck("enterprise_installation_user_accounts.id", :user_id)
    return nil if rows.empty?
    GHESCommitters.new(user_ids: rows.filter_map { |_, user_id| user_id }, unmatched: rows.filter_map { |id, user_id| id if user_id.nil? })
  end

  # Returns the set of active committer user IDs associated with the billable entity of
  # the license.
  sig { returns(T::Array[Integer]) }
  memoize def active_committer_user_ids
    return [] unless purchased?
    return [] if @billable_entity.nil?
    entity_type = GitHub::Turboghas.entity_type_for(@billable_entity)
    response = GitHub::Turboghas.client.get_active_committers(entity_id: @billable_entity.id, entity_type: entity_type, features: @sku.features)
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?
    response.data.users.map(&:id)
  end

  sig { params(repository_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
  def additional_committers_per_repository(repository_ids:)
    return {} if @billable_entity.nil?
    entity_type = GitHub::Turboghas.entity_type_for(@billable_entity)
    response = GitHub::Turboghas.client.get_additional_committers_per_repository(entity_id: @billable_entity.id, entity_type:, repository_ids:, features: @sku.features)
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?

    response.data.repositories.to_h { |repo| [repo.id, repo.additional_committers] }
  end
end
