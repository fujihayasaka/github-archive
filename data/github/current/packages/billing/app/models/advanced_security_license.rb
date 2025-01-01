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

  sig { params(owner: Billing::Types::Account).void }
  def initialize(owner)
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
    elsif entity.is_a?(User) && entity.is_enterprise_managed?
      entity.enterprise_managed_business
    elsif entity.is_a?(Organization) || entity.is_a?(Business)
      entity
    end
  end

  sig do
    params(
      entity: Billing::Types::Account,
      repository_ids: T.nilable(T::Array[Integer]),
    ).returns(::Turboghas::Proto::GetSummaryResponse)
  end
  def self.summary(entity:, repository_ids: nil)
    entity_type = GitHub::Turboghas.entity_type_for(entity)
    customer_id = entity.customer&.id if !entity.is_a?(User) && entity.advanced_security_metered_for_entity?
    additional_user_ids = entity.advanced_security_business_user_ids if entity.is_a?(Business)

    response = GitHub::Turboghas.client.get_summary(
      entity_id: entity.id,
      entity_type: entity_type,
      repository_ids: repository_ids,
      customer_id:,
      additional_user_ids:,
    )
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?
    response.data.tap do |data|
      unless entity.advanced_security_purchased?
        data.active_committers = 0
        data.additional_metered_committers = 0
      end
    end
  end

  sig do
    params(
      entity: T.nilable(Billing::Types::Account),
      repository_ids: T.nilable(T::Array[Integer]),
    ).returns(Integer)
  end
  def self.contributors_for_repos(entity:, repository_ids:)
    return 0 if entity.nil?
    return 0 if repository_ids.blank?
    AdvancedSecurityLicense.summary(entity: entity, repository_ids: repository_ids).active_committers
  end

  sig do
    params(
      owner: Billing::Types::Account,
    ).returns(Integer)
  end
  def self.seat_usage_increase_if_advanced_security_enabled_for_all_repos(owner:)
    return 0 if owner.nil?
    owner.advanced_security_summary.additional_committers
  end

  # Calculates how many extra GHAS seats would be used / contributors would be billed for if
  # GHAS were to be enabled on the given repository.
  #
  # Returns 0 if GHAS is not purchased or is already enabled for the repository.
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
    ).returns(Integer)
  end
  def self.seat_usage_increase_if_advanced_security_enabled_for_repos(owner:, repo_ids:)
    return 0 if owner.nil?
    # if the caller deliberately passes in an empty list then return zero
    # if they pass in nil, return the full user count
    return 0 if repo_ids.try(:empty?)

    AdvancedSecurityLicense.summary(entity: owner, repository_ids: repo_ids).additional_committers
  end

  sig do
    params(
      repo_ids: T::Array[Integer],
    ).returns(Integer)
  end
  def seat_usage_increase_if_advanced_security_enabled_for_repos(repo_ids)
    AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_repos(owner: T.must(@billable_entity), repo_ids: repo_ids)
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
  memoize def seats
    # This covers users on dotcom since, unlike orgs or businesses, they can't purchase GHAS seats.
    return 0 unless @billable_entity&.advanced_security_purchased?
    return GitHub::Enterprise.license.advanced_security_seats if GitHub.enterprise?
    @billable_entity.advanced_security_seats_for_entity
  end

  # Public: Has GHAS been purchased with unlimited seats?
  sig { returns(T::Boolean) }
  memoize def unlimited_seats?
    if @billable_entity&.advanced_security_seats_stored_on_subscription_item?
      return @billable_entity.has_active_advanced_security_trial? || false
    end
    (@billable_entity&.advanced_security_purchased? || false) && seats == 0
  end

  # Public: Has GHAS been enabled via a sales-led trial?
  sig { returns(T::Boolean) }
  def has_sales_serve_trial?
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
    @billable_entity.advanced_security_seats_used
  end

  sig { returns(Integer) }
  memoize def additional_metered_seats
    return 0 if GitHub.enterprise?
    return 0 if @billable_entity.nil?
    @billable_entity.advanced_security_additional_metered_seats_used
  end

  sig { returns(::Turboghas::Proto::GetSummaryResponse) }
  memoize def summary
    AdvancedSecurityLicense.summary(entity: T.must(@billable_entity))
  end

  # Public: Are more Advanced Security seats being used than have been purchased?
  sig { returns(T::Boolean) }
  def allowance_exceeded?
    return false unless @billable_entity&.advanced_security_purchased?
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
    user_query = User.from("users FORCE INDEX(PRIMARY)").where(type: User, suspended_at: nil, disabled: false)

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
    const :unmatched, Integer
  end

  sig { returns(T.nilable(GHESCommitters)) }
  def ghes_committers
    return nil if @billable_entity.nil?
    # group by user_id as it is not a unique column
    counts = @billable_entity.advanced_security_business_user_accounts.group(BusinessUserAccount.arel_table[:user_id]).count("1")
    return nil if counts.empty?
    # Get the count of business_user_account rows that do not point to a GHEC account (their user_id is NULL)
    # and remove the nil key from the counts of matching of user IDs.
    unmatched = counts.delete(nil) { 0 }
    GHESCommitters.new(user_ids: counts.keys, unmatched:)
  end

  # Returns the set of active committer user IDs associated with the billable entity of
  # the license.
  sig { returns(T::Array[Integer]) }
  memoize def active_committer_user_ids
    return [] unless @billable_entity&.advanced_security_purchased?
    entity_type = GitHub::Turboghas.entity_type_for(@billable_entity)
    response = GitHub::Turboghas.client.get_active_committers(entity_id: @billable_entity.id, entity_type: entity_type)
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?
    response.data.users.map(&:id)
  end

  sig { params(repository_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
  def additional_committers_per_repository(repository_ids:)
    entity_type = GitHub::Turboghas.entity_type_for(@billable_entity)
    response = GitHub::Turboghas.client.get_additional_committers_per_repository(entity_id: T.must(@billable_entity).id, entity_type:, repository_ids:)
    raise TurboghasError.new(response.error) if response.error.present?
    raise TurboghasError.new("No data returned") if response.nil?

    response.data.repositories.to_h { |repo| [repo.id, repo.additional_committers] }
  end
end
