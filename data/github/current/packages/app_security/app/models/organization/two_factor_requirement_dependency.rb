# typed: true
# frozen_string_literal: true

# This is a collection of public and private methods related to the two factor
# requirement feature for organizations.
#
# The following public methods should be used:
#
# * Organization#two_factor_requirement_enabled?
# * Organization#enable_two_factor_requirement
# * Organization#disable_two_factor_requirement
#
# DisableTwoFactorRequirementJob is also performed via the
# enterprise:disable_two_factor_requirement rake task on a configuration run on
# Enterprise Server installations, which checks whether the current
# authentication mode supports 2FA and if not, disables 2FA on the global
# business as well as on any orgs that have 2FA enabled.

module Organization::TwoFactorRequirementDependency
  include Kernel
  extend T::Helpers
  requires_ancestor { Organization }
  TWO_FA_USER_COUNT_LIMIT = 2001

  # Public: Enables 2fa requirement for the organization.
  def enable_two_factor_requirement(actor:, log_event: false)
    enable_two_factor_required(actor: actor, log_event: log_event)

    yield if block_given?
  end

  # Public: Disables the 2fa requirement for the organization.
  def disable_two_factor_requirement(actor:, log_event: false)
    disabled_2fa = disable_two_factor_required(actor: actor, log_event: log_event)

    clear_disallowed_two_factor_methods(actor: actor, log_event: insecure_two_factor_methods_disallowed?)

    disabled_2fa
  end

  # Public: Do any users with 2fa disabled exist?
  #
  # Returns a Boolean.
  def users_with_two_factor_disabled_exist?(user_ids, batch_size: 10_000)
    User.batched_scope(:id, values: user_ids, batch_size: batch_size) { |scope| scope.two_factor_disabled }.any?
  end

  # Public: Count users with 2fa disabled
  #
  # Returns an Integer.
  def users_with_two_factor_disabled_count(user_ids, batch_size: 10_000)
    unique_ids = Set.new(user_ids).to_a
    unique_ids.size - TwoFactorCredential.batched_scope(:user_id, values: unique_ids, batch_size: batch_size).count
  end

  # Public: Direct members with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def members_with_two_factor_disabled(limit: nil)
    members(limit: limit).two_factor_disabled
  end

  # Public: Direct members with 2fa disabled.
  #
  # Returns an Integer
  def members_with_two_factor_disabled_count
    users_with_two_factor_disabled_count(member_ids)
  end

  # Public: Do any direct members with 2fa disabled exist?
  #
  # Returns a Boolean.
  def members_with_two_factor_disabled_exist?
    users_with_two_factor_disabled_exist?(member_ids)
  end

  # Public: Outside collaborators with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def outside_collaborators_with_two_factor_disabled(limit: nil)
    outside_collaborators.limit(limit).two_factor_disabled
  end

  # Public: Number of outside collaborators with 2fa disabled.
  #
  # Returns an Integer
  def outside_collaborators_with_two_factor_disabled_count
    users_with_two_factor_disabled_count(outside_collaborator_ids)
  end

  # Public: Do any outside collaborators with 2fa disabled exist?
  #
  # Returns a Boolean.
  def outside_collaborators_with_two_factor_disabled_exist?
    users_with_two_factor_disabled_exist?(outside_collaborator_ids)
  end

  # Public: Hiring managers with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def billing_managers_with_two_factor_disabled(limit: nil)
    billing.members(limit: limit).two_factor_disabled
  end

  # Public: Number of hiring managers with 2fa disabled.
  #
  # Returns an Integer
  def billing_managers_with_two_factor_disabled_count
    users_with_two_factor_disabled_count(billing_manager_ids)
  end

  # Public: Do any hiring managers with 2fa disabled exist?
  #
  # Returns a Boolean.
  def billing_managers_with_two_factor_disabled_exist?
    users_with_two_factor_disabled_exist?(billing_manager_ids)
  end

  # Public: Admins with 2FA enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def admins_with_two_factor_enabled(limit: nil)
    admins(limit: limit).two_factor_enabled
  end

  # Public: Billing managers with 2fa enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def billing_managers_with_two_factor_enabled(limit: nil)
    billing.members(limit: limit).two_factor_enabled
  end

  # Public: Direct members with 2fa enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def members_with_two_factor_enabled(limit: nil)
    members(limit: limit).two_factor_enabled
  end

  # Public: An array of scopes that represent the users affiliated with the
  # organization and have 2fa disabled.
  #
  # Returns an Array of ActiveRecord::Relation objects.
  def affiliated_users_with_two_factor_disabled_scopes(limit: nil)
    [
      members_with_two_factor_disabled(limit: limit),
      outside_collaborators_with_two_factor_disabled(limit: limit),
      billing_managers_with_two_factor_disabled(limit: limit),
    ]
  end

  # Public: The number of users affiliated with the organization that
  # have 2fa disabled.
  #
  # Returns an Integer.
  def affiliated_user_ids_with_two_factor_disabled_counts
    users_with_two_factor_disabled_count(member_ids.to_a + outside_collaborator_ids.to_a + billing_manager_ids.to_a)
  end

  # Public: Affiliated users with 2FA disabled
  #
  # Returns a Boolean.
  def affiliated_users_with_two_factor_disabled
    affiliated_users_with_two_factor_disabled_scopes.
      inject(Set.new) do |users, scope|
        users.merge(scope.all)
      end.to_a
  end

  # Public: The number of unique affiliated users with 2FA disabled
  #
  # Returns an Integer, up to TWO_FA_USER_COUNT_LIMIT
  def affiliated_users_with_two_factor_disabled_count
    subqueries = affiliated_users_with_two_factor_disabled_scopes.map do |query|
      query.select(:id).limit(TWO_FA_USER_COUNT_LIMIT).to_sql
    end
    subqueries = subqueries.reject(&:blank?).join(") UNION (")

    self.class.connection.execute("SELECT COUNT(*) FROM ((#{subqueries}) LIMIT #{TWO_FA_USER_COUNT_LIMIT}) AS non_2fa_users").to_a.flatten.first
  end

  # Public: Does this organization need enforcement to enable the two factor
  # requirement?
  #
  # Returns a Boolean.
  def affiliated_users_with_two_factor_disabled_exist?
    return true if members_with_two_factor_disabled_exist?
    return true if outside_collaborators_with_two_factor_disabled_exist?
    return true if billing_managers_with_two_factor_disabled_exist?
    false
  end

  # Public: Returns true if this organization's 2FA Authentication requirement
  #         (if any) can be met by the given PROSPECTIVE_MEMBER.
  #
  # prospective_member - a User
  #
  # Returns a Boolean.
  def two_factor_requirement_met_by?(prospective_member)
    return true if !two_factor_requirement_enabled?
    return false if prospective_member.nil?
    prospective_member.two_factor_authentication_enabled?
  end

  # Public: Returns true if the organization's 2FA disallowed methods policy is enabled
  # and prospective member has disallowed 2FA method(s).
  #
  # prospective_member - a User
  #
  # Returns a Boolean.
  def disallowed_two_factor_method_used_by?(prospective_member)
    return false unless can_disallow_two_factor_methods?
    return false if prospective_member.nil?
    return false unless prospective_member.two_factor_authentication_enabled?

    disallowed_methods = get_two_factor_disallowed_methods
    return false if disallowed_methods.empty?

    prospective_member.has_any_given_2fa_methods_configured?(disallowed_methods)
  end

  def async_two_factor_requirement_met_by?(prospective_member)
    T.unsafe(self).async_two_factor_requirement_enabled?.then do |two_fa_enabled|
      next Promise.resolve(true) if !two_fa_enabled
      next Promise.resolve(false) if prospective_member.nil?
      next Promise.resolve(prospective_member.async_two_factor_authentication_enabled?)
    end
  end

  # Public: Can the two factor requirement be enabled for this organization?
  #
  # At least one admin in the organization must have two factor authentication
  # enabled for the two factor requirement be enabled for this organization.
  #
  # Returns a Boolean.
  def can_two_factor_requirement_be_enabled?
    admins.any?(&:two_factor_authentication_enabled?)
  end

  # Public: Is the two factor requirement currently being enforced?
  #
  # Returns a Boolean.
  def enforcing_two_factor_requirement?
    return false unless enforce_two_factor_requirement_job_status.present?

    !enforce_two_factor_requirement_job_status.finished?
  end

  # Public: The JobStatus for the two factor requirement enforcement job.
  #
  # Returns a JobStatus or nil.
  def enforce_two_factor_requirement_job_status
    @enforce_two_factor_requirement_job_status ||= begin
      status = EnforceTwoFactorRequirementOnOrganizationJob.status(self)
      return status if status && !status.finished?

      biz_status = EnforceTwoFactorRequirementOnBusinessJob.status(self.business) if self.business
      return status if !biz_status.present?

      # Defer to any business level enforcement job if present
      biz_status
    end
  end

  # Public: Is two factor enforcement enabled for the org or the business that
  # owns it?
  #
  # Returns a Boolen
  def two_factor_cap_enforcement_enabled?
    T.bind(self, Organization)
    GitHub.tracer.in_span("Organization#two_factor_cap_enforcement_enabled?") do |_span|
      return true if self.feature_enabled?(:two_factor_cap_enforcement)
      return true if self.business&.feature_enabled?(:two_factor_cap_enforcement)

      false
    end
  end

  def async_two_factor_cap_enforcement_enabled?
    T.bind(self, Organization)
    return Promise.resolve(true) if self.feature_enabled?(:two_factor_cap_enforcement)
    async_business.then do |business|
      return Promise.resolve(true) if business&.feature_enabled?(:two_factor_cap_enforcement)
    end

    Promise.resolve(false)
  end

  # Public: Are members without 2fa allowed to join the organization? This can
  # only be true if the org has 2fa enforcement enabled already
  #
  # Returns a Boolen
  def members_without_2fa_allowed?
    T.bind(self, Organization)
    return false unless two_factor_cap_enforcement_enabled?
    return true if self.feature_enabled?(:members_without_2fa_allowed)
    return true if business&.feature_enabled?(:members_without_2fa_allowed)

    false
  end

  def async_members_without_2fa_allowed?
    T.bind(self, Organization)
    return Promise.resolve(false) unless async_two_factor_cap_enforcement_enabled?.sync
    return Promise.resolve(true) if self.feature_enabled?(:members_without_2fa_allowed)
    async_business.then do |business|
      return Promise.resolve(true) if business&.feature_enabled?(:members_without_2fa_allowed)
    end

    Promise.resolve(false)
  end

  # Public: Is the two factor secure methods restriction available for the organization?
  #
  # Returns a Boolen
  def can_disallow_two_factor_methods?
    async_can_disallow_two_factor_methods?.sync
  end

  def async_can_disallow_two_factor_methods?
    T.bind(self, Organization)
    return Promise.resolve(false) unless members_without_2fa_allowed?
    return Promise.resolve(true) if self.feature_enabled?(:disallow_two_factor_methods)
    self.async_business.then do |business|
      next Promise.resolve(business&.feature_enabled?(:disallow_two_factor_methods))
    end
  end

  def enforce_two_factor_methods_policy?
    async_enforce_two_factor_methods_policy?.sync
  end

  # Method exclusively for 2FA CAP policy to invoke, checking CAP enforcement of disallowed methods compared to UI feature allowing changes
  def async_enforce_two_factor_methods_policy?
    T.bind(self, Organization)
    Promise.resolve(self.feature_enabled?(:enforce_disallow_two_factor_methods))
  end

  def disallow_insecure_two_factor_methods(actor:)
    T.bind(self, Organization)
    EnforceTwoFactorRequirementOnOrganizationJob.perform_later(self, actor, disallowed_methods: [Configurable::TwoFactorDisallowedMethods::INSECURE])
  end

  # Public: Is 2fa enabled on the business that owns the organisation?
  #
  # Returns Boolen
  def two_factor_enabled_on_business?
    self.business&.two_factor_requirement_enabled?
  end
end
