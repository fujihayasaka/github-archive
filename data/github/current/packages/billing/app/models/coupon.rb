# typed: strict
# frozen_string_literal: true

# A Coupon can be redeemed by a User to get a discount on their
# monthly plan. Once applied, a CouponRedemption record is created to keep
# track of who redeemed what.
class Coupon < ApplicationRecord::Domain::Users
  include Billing::ICoupon

  include GitHub::Memoizer
  include Instrumentation::Model
  include GitHub::Validations
  include Coupon::ZuoraDependency

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_deletion, on: :destroy

  # If you change this, don't forget to change the regexp in routes.rb
  FORMAT_CHARACTERS = 'a-z0-9\._\-+:*!&<>()^'

  validates_uniqueness_of   :code, case_sensitive: false
  validates_presence_of     :code
  validates_format_of       :code, with: /\A[#{FORMAT_CHARACTERS}]+\z/i
  validates_presence_of     :note
  validates_presence_of     :discount
  validates_numericality_of :discount
  validates_presence_of     :duration
  validates_presence_of     :limit
  validates_presence_of     :expires_at

  validates :code, unicode3: true
  validates :plan, unicode3: true
  validates :note, unicode3: true

  GHEC_PRODUCT_TARGET = T.let({ product_type: "github.plan", product_key: "business_plus" }.freeze, T::Hash[Symbol, String])
  STUDENT_DEVELOPER_PACK_NAME = "students-"
  FACULTY_DEVELOPER_PACK_NAME = "faculty-"
  TEACHER_TOOLBOX = %r{students-\d{4}|faculty-\d{4}|classroom-curium|research-*}
  NON_PROFIT_CODE = "notsoprofitable"
  EDUCATION_GROUP_NAMES = T.let(%w(education-individual education-org education-promo), T::Array[String])
  SALES_SERVE_GROUP_NAME = "sales-serve"
  SELF_SERVE_BUSINESS_PLUS_GROUP_NAMES = T.let(%w[microsoft startup-program], T::Array[String])
  SELF_SERVE_BUSINESS_PLUS_CODE_NAMES = %r{gfs|ISV-Success-Program-|GitHub-and-Microsoft-Love-Startups-}
  BUSINESS_PLUS_ONLY_GROUP_NAMES = T.let([
    SALES_SERVE_GROUP_NAME,
    "dreamforce-2017",
  ], T::Array[String])

  # The possible values for the group field.
  GROUP_NAMES = T.let((EDUCATION_GROUP_NAMES + SELF_SERVE_BUSINESS_PLUS_GROUP_NAMES + %w(
    boxdev2014
    cisco-devnet
    cloneageddon
    community
    copilot-pricing
    diversity
    enterprise
    expired
    facebook-fbstart
    fbstart2016
    gifts
    hackathons
    ibm-devworks
    incubators
    internal
    prepaid
    prizes
    sales
    security
    si-bulk
    support
    workshop)).sort, T::Array[String])

  validates_inclusion_of :group, in: (BUSINESS_PLUS_ONLY_GROUP_NAMES + GROUP_NAMES)
  validate :sales_serve_requires_ghec_product_target

  SALES_SERVE_DURATION = 30

  belongs_to :coupon_batch, optional: true

  has_many :coupon_redemptions, dependent: :destroy
  has_many :users, through: :coupon_redemptions, source: :billable_entity, source_type: "User", disable_joins: true

  has_one :product_target, dependent: :destroy, class_name: "CouponProductTarget", inverse_of: :coupon, autosave: false
  validates_associated :product_target, on: :create

  scope :multi_use,          -> { where("`coupons`.`limit` > 1") }
  scope :active,             -> { where("expires_at IS NULL OR expires_at > ?", GitHub::Billing.now) }
  scope :expired,            -> { where("expires_at <= ?", GitHub::Billing.now) }
  scope :for_group,          -> (group) { where(group: group) }
  scope :education,          -> { where(group: EDUCATION_GROUP_NAMES) }
  scope :business_plus_only, -> { where(group: BUSINESS_PLUS_ONLY_GROUP_NAMES) }

  # When product_target_product_uuid is nil
  # it means the coupon is not tied to any specific product and should use the default coupon behavior
  # which is to discount via the main coupon product uuid in the product catalog
  sig { returns(T.nilable(Billing::ProductUUID)) }
  def product_target_product_uuid
    product_target&.product_uuid
  end

  sig { returns(String) }
  def human_target
    return T.must(product_target).product_name if has_product_target?
    return "GitHub #{T.must(plan).titleized_display_name}" if plan.present?
    "GitHub paid plans"
  end

  # The product type for looking up the ProductUUID record
  sig { override.returns(String) }
  def product_type
    "github.coupon"
  end

  sig { returns(String) }
  def base_product_key
    percentage? ? "percentage" : "fixed_amount"
  end

  # The product key for looking up the ProductUUID record
  sig { override.returns(String) }
  memoize def product_key
    if product_target = self.product_target
      "#{base_product_key}.#{product_target.product_type}.#{product_target.product_key}"
    else
      base_product_key
    end
  end

  sig { returns(T::Array[Billing::ProductUUID]) }
  def product_target_product_uuids
    if product_target = self.product_target
      product_target.product_uuids.to_a
    else
      ::Billing::ProductUUID.discountable.to_a
    end
  end

  sig { override.returns(T.nilable(String)) }
  def product_target_name
    product_target&.product_name
  end

  sig { override.returns(T::Boolean) }
  def has_product_target?
    product_target.present?
  end

  # Finds a coupon from a code. If passed a Coupon, returns it.
  sig { params(code: T.nilable(T.any(String, Coupon))).returns(T.nilable(Coupon)) }
  def self.find_by_code(code)  # rubocop:disable GitHub/FindByDef
    return nil if code.blank?
    code.is_a?(Coupon) ? code : where(code: code).first
  end

  # Cleans the code of an old coupon that may have an invalid code by
  # replacing invalid characters with '-'. See #16950.
  sig { params(code: T.nilable(String)).returns(T.nilable(String)) }
  def self.clean_old_code(code)
    code.gsub(/[^#{FORMAT_CHARACTERS}]/i, "-") if code
  end

  # Determine that the code is in a valid format.
  sig { params(code: T.nilable(String)).returns(T.nilable(T::Boolean)) }
  def self.valid_code?(code)
    if code
      !!code.match(/\A[#{FORMAT_CHARACTERS}]+\z/i)
    else
      false
    end
  end

  # Returns the number of redemptions for this coupon.
  # The count will query the database only until the collection is loaded
  sig { returns(Integer) }
  def redeemed_count
    coupon_redemptions.size
  end

  sig { returns(T::Boolean) }
  def clean_code!
    self.update_attribute(:code, Coupon.clean_old_code(code))
  end

  # Every coupon has a code which can be used to redeem it.
  # If no code is provided at the time of creation, one will be provided
  # for you.
  sig { override.returns(String) }
  def code
    self[:code] ||= SecureRandom.hex(4)[0, 7]
  end
  alias_method :to_s, :code
  alias_method :to_param, :code

  # Is this coupon for a free trial? Free trials allow a user to
  # use a paid plan without entering their CC#.
  #
  # Aliased as one_hundred_percent_discount? for different use cases than
  # just trial? checking.
  sig { returns(T::Boolean) }
  def trial?
    !!(discount == 1.0)
  end
  alias :one_hundred_percent_discount? :trial?

  sig { returns(T::Boolean) }
  def percentage?
    discount.to_f <= 1.0
  end

  # Returns true if this coupon is used for non-profit organizations.
  sig { returns(T::Boolean) }
  def non_profit?
    code == NON_PROFIT_CODE
  end

  # The coupons's lifespan in days. Defaults to 31
  sig { override.returns(Integer) }
  def duration
    self[:duration] ||= 31
  end

  # How many times this coupon may be redeemed. Defaults to 1
  sig { override.returns(Integer) }
  def limit
    self[:limit] ||= 1
  end

  # When this coupon expires. Defaults to 1 year from today
  sig { override.returns(ActiveSupport::TimeWithZone) }
  def expires_at
    self[:expires_at] ||= GitHub::Billing.now + 1.year
    self[:expires_at].in_billing_timezone
  end

  # Public: Setter for this Coupon's plan
  sig { params(new_plan: T.nilable(T.any(String, GitHub::Plan))).returns(T.nilable(String)) }
  def plan=(new_plan)
    write_attribute(:plan, new_plan.to_s)
  end

  # Public: Getter for this Coupon's plan.
  sig { override.returns(T.nilable(GitHub::Plan)) }
  def plan
    GitHub::Plan.find(read_attribute(:plan))
  end

  # Allow discounts to be set using strings such as "$12" or "50%"
  # by converting it to number as soon as it's set.
  sig { params(discount: T.nilable(T.any(String, ::Billing::Types::Numeric))).void }
  def discount=(discount)
    if !discount.is_a? String
      return self[:discount] = discount
    end

    if discount.include? "%"
      super discount.to_f / 100
    elsif discount.include? "$"
      super discount.gsub(/[^\d.]/, "").to_f
    elsif !discount.empty?
      super discount.to_f
    end
  end

  # A pretty string we can use to represent this discount,
  # either as a % value or a set dollar amount.
  sig { returns(T.nilable(String)) }
  def human_discount
    discount = self.discount
    return unless discount
    if discount > 1
      "$%.02f" % discount
    else
      "#{discount_in_cents.to_i}%"
    end
  end

  sig { returns(Integer) }
  def discount_in_cents
    (discount.to_f * 100).to_i
  end

  # The display name of plan specific coupon.
  sig { returns(T.nilable(String)) }
  def plan_display_name
    plan = self.plan
    plan && plan.display_name.humanize
  end

  FOREVER_DURATION = 29970

  # Durations can be any number of days, but not all
  # durations are created equal. Here are some suggestions.
  FUN_DURATIONS = T.let({
    7     => "7-day",
    14    => "14-day",
    30    => "30-day",
    45    => "45-day",
    31    => "1 month",
    60    => "2 months",
    90    => "3 months",
    120   => "4 months",
    150   => "5 months",
    180   => "6 months",
    210   => "7 months",
    240   => "8 months",
    270   => "9 months",
    300   => "10 months",
    330   => "11 months",
    365   => "1 year",
    730   => "2 years",
    FOREVER_DURATION => "Forever",
  }, T::Hash[Integer, String])

  # Need our FUN_DURATIONS nice and neat? This'll give 'em to you in
  # order of least (one day) to more (1 year).
  sig { returns(T::Array[T::Array[T.untyped]]) }
  def fun_durations
    FUN_DURATIONS.to_a.sort.map { |i| i.reverse }
  end

  # Is the current duration fun? Does it appear in FUN_DURATIONS?
  sig { returns(T::Boolean) }
  def fun_duration?
    !!FUN_DURATIONS[duration]
  end

  # The duration as something appropriate for human consumption.
  sig { returns(String) }
  def human_duration
    FUN_DURATIONS[duration] ||
      (duration > 30 ? "#{duration / 30} months" : "#{duration} days")
  end

  # Will this coupon ever expire?
  sig { returns(T::Boolean) }
  def will_expire?
    duration < FOREVER_DURATION
  end

  # Can the actor perform the redemption? This doesn't guarantee that the coupon
  # can be applied to a given user, just that the redemption can be perfomed
  # by the actor.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def redeemable_by?(actor)
    if staff_actor_only?
      !!actor.try(:site_admin?) || !!actor.try(:biztools_user?)
    else
      true
    end
  end

  # Has this coupon expired?
  sig { returns(T::Boolean) }
  def expired?
    !expires_at.nil? && expires_at < GitHub::Billing.now
  end

  # The expiration date as something appropriate for human consumption.
  sig { returns(T.any(String, Date)) }
  def human_expires_at
    return "never" if expires_at.nil?
    return "expired" if expired?
    expires_at.to_date
  end

  # The expiration date as something appropriate for human editing.
  sig { returns(T.nilable(String)) }
  def form_expires_at
    expires_at.to_date.iso8601 unless expires_at.nil?
  end

  # Whether this coupon can be applied to user accounts.
  sig { returns(T::Boolean) }
  def user_coupon?
    plan = self.plan
    !plan || plan.user_plan?
  end

  # Whether this coupon can be applied to org accounts.
  sig { returns(T::Boolean) }
  def org_coupon?
    return false if has_product_target?

    plan = self.plan
    !plan || plan.org_plan?
  end

  # Public: Returns true if this coupon is an education coupon
  sig { returns(T::Boolean) }
  def education_coupon?
    EDUCATION_GROUP_NAMES.include?(group)
  end

  # Public: Returns true if this coupon is a sales-serve coupon
  sig { returns(T::Boolean) }
  def business_plus_only_coupon?
    BUSINESS_PLUS_ONLY_GROUP_NAMES.include?(group)
  end
  alias_method :ghec_only_group?, :business_plus_only_coupon?

  sig { returns(T::Boolean) }
  def sales_serve_coupon?
    SALES_SERVE_GROUP_NAME == group
  end

  # A coupon can trigger the creation of an Enterprise account in two cases:
  # 1. The coupon is part of an eligible group, and has an eligible code, regardless of the plan selected on coupon creation.
  # 2. The coupon is part of an eligible group, and has been specified to be for the business_plus plan.
  sig { returns(T::Boolean) }
  def self_serve_business_plus_coupon?
    (SELF_SERVE_BUSINESS_PLUS_GROUP_NAMES.include?(group) && SELF_SERVE_BUSINESS_PLUS_CODE_NAMES.match?(code)) ||
    (SELF_SERVE_BUSINESS_PLUS_GROUP_NAMES.include?(group) && plan&.name == "business_plus")
  end

  # Whether this coupon can only be applied to user accounts.
  sig { returns(T::Boolean) }
  def user_only?
    (user_coupon? && !org_coupon?) || has_product_target?
  end

  # Whether this coupon can only be applied to org accounts.
  sig { returns(T::Boolean) }
  def org_only?
    !user_coupon? && org_coupon?
  end

  # Public: Is this coupon tied to a specific plan?
  sig { override.returns(T::Boolean) }
  def plan_specific?
    plan.present?
  end

  # Whether this coupon can be applied to both user and org accounts.
  sig { returns(T::Boolean) }
  def all_accounts?
    user_coupon? && org_coupon?
  end

  # Can this coupon be used with the target plan
  sig { params(target_plan: GitHub::Plan).returns(T::Boolean) }
  def applicable_to?(target_plan)
    !plan_specific? || !!(plan && target_plan == plan)
  end

  # User's accounts that are eligible for the sales-serve coupon group
  sig { params(user: User).returns(T::Array[Organization]) }
  def business_plus_only_eligible_accounts(user)
    user.owned_or_billing_manager_organizations.reject do |org|
      case self.group
      when SALES_SERVE_GROUP_NAME
        org.invoiced? || org.business_plus? || !org.per_seat_plan_only? || org.has_an_active_coupon?
      else
        true
      end
    end
  end

  # User's accounts that are eligible for this coupon.
  sig { params(user: User).returns(T.any(T::Array[User], T::Array[Business])) }
  def eligible_accounts(user)
    return business_plus_only_eligible_accounts(user) if business_plus_only_coupon?
    if self_serve_business_plus_coupon?
      return eligible_self_serve_enterprise_accounts(user)
    end

    plan = self.plan

    if plan.present?
      if plan.org_plan? || (self_serve_business_plus_coupon? && plan.hidden_org_plan?)
        user.owned_organizations.reject(&:invoiced?)
      else
        [user]
      end
    else
      [user] + user.owned_organizations.reject do |org|
        org.invoiced? || org.business_plus?
      end
    end
  end

  # User's enterprise accounts that are eligible for the self-serve business_plus coupon group
  sig { params(user: User).returns(T::Array[Business]) }
  def eligible_self_serve_enterprise_accounts(user)
    return [] unless self_serve_business_plus_coupon?

    user.businesses(membership_type: :admin).select do |business|
      eligible_business?(business)
    end
  end

  # Is the business eligible for the self-serve business_plus coupon group
  sig { params(business: Business).returns(T::Boolean) }
  def eligible_business?(business)
    return false if business.invoiced? || business.has_an_active_coupon? || business.metered_plan?
    true
  end

  sig { params(product_type: String, product_key: String).void }
  def assign_product_target!(product_type:, product_key:)
    # TODO: How to handle these magic strings
    if product_type == Coupon::GHEC_PRODUCT_TARGET[:product_type] && product_key == Coupon::GHEC_PRODUCT_TARGET[:product_key]
      self.group = SALES_SERVE_GROUP_NAME if group.blank?
      self.plan = GitHub::Plan.business_plus
    else
      self.build_product_target(coupon: self, product_type: product_type, product_key: product_key)
    end
  end

  sig { void }
  def sales_serve_requires_ghec_product_target
    return unless group == SALES_SERVE_GROUP_NAME
    return if plan == GitHub::Plan.business_plus

    errors.add(:group, "'sales-serve' group is reserved for GHEC-only coupons")
  end

  # Other high volume coupons can be added here BUT DO NOT add coupons where we need the limit to be
  # up to date for concurrent limit checks, these are coupons that have ULTRA HIGH limits!
  HIGH_VOLUME_COUPONS = T.let(["revoked"], T::Array[String])

  # Should the coupon decrement be skipped?
  # Some single coupons can be redeemed multiple times quickly by automated tools,
  # this causes row contention, slow/killed queries and so to relieve this the decrement could be skipped.
  sig { returns(T::Boolean) }
  def skip_limit_decrement?
    HIGH_VOLUME_COUPONS.include?(code)
  end

  private

  sig { void }
  def instrument_creation
    instrument :create
    tags = limit > 1 ? ["multi_use:true"] : ["multi_use:false"]
    GitHub.dogstats.increment("coupon.create", tags: tags)
  end

  sig { void }
  def instrument_update
    instrument :update
  end

  sig { void }
  def instrument_deletion
    instrument :destroy
  end

  # Default instrumentation payload
  sig { returns(T::Hash[Symbol, T.any(String, Integer, T::Boolean)]) }
  def event_payload
    {
      id: self.id,
      group: self.group,
      limit: self.limit,
      redeemed_count: self.redeemed_count,
      expired: self.expired?,
    }
  end
end
