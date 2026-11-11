# typed: true
# frozen_string_literal: true

# A class to encapsulate logic around chaining scopes based on filters expressed
# in the passed-in query object.
class Organization::People::Filter
  include GitHub::Memoizer


  def initialize(query:, base_relation: nil)
    @query = query
    @base_relation = base_relation || query.organization.people
  end

  # Public: Build a scope of users based on the query object that gets passed
  # in. Apply clauses to the relation we build up based on the state of the
  # query object.
  #
  # Drawing a lot of inspiration from https://thoughtbot.com/blog/using-yieldself-for-composable-activerecord-relations
  #
  # Returns: ActiveRecord::Relation of Users
  def call
    @base_relation
      .order("users.login")
      .then(&method(:two_factor_disabled_clause))
      .then(&method(:two_factor_enabled_clause))
      .then(&method(:two_factor_required_clause))
      .then(&method(:two_factor_secure_clause))
      .then(&method(:two_factor_insecure_clause))
      .then(&method(:external_identity_linked_clause))
      .then(&method(:external_identity_unlinked_clause))
      .then(&method(:organization_membership_group_clause))
      .then(&method(:organization_membership_admin_clause))
  end

  private

  def two_factor_disabled_clause(relation)
    if @query.two_factor_disabled_scope?
      not_enabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_disabled(user_ids: relation.pluck(:id))
      required_ids = TwoFactorUserQuery.user_ids_with_two_factor_required(user_ids: not_enabled_ids)
      relation.where(id: not_enabled_ids - required_ids)
    else
      relation
    end
  end

  def two_factor_enabled_clause(relation)
    if @query.two_factor_enabled_scope?
      relation.where(id: TwoFactorUserQuery.user_ids_with_two_factor_enabled(user_ids: relation.pluck(:id)))
    else
      relation
    end
  end

  def two_factor_required_clause(relation)
    if @query.two_factor_required_scope?
      disabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_disabled(user_ids: relation.pluck(:id))
      relation.where(id: TwoFactorUserQuery.user_ids_with_two_factor_required(user_ids: disabled_ids))
    else
      relation
    end
  end

  def two_factor_secure_clause(relation)
    if @query.two_factor_secure_scope?
      enabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_enabled(user_ids: relation.pluck(:id))
      insecure_ids = TwoFactorUserQuery.user_ids_with_insecure_two_factor_method(user_ids: enabled_ids)
      relation.where(id: enabled_ids - insecure_ids)
    else
      relation
    end
  end

  def two_factor_insecure_clause(relation)
    if @query.two_factor_insecure_scope?
      enabled_ids = TwoFactorUserQuery.user_ids_with_two_factor_enabled(user_ids: relation.pluck(:id))
      insecure_ids = TwoFactorUserQuery.user_ids_with_insecure_two_factor_method(user_ids: enabled_ids)
      relation.where(id: insecure_ids)
    else
      relation
    end
  end

  def external_identity_linked_clause(relation)
    if @query.external_identity_linked_scope? && saml_provider.present?
      relation
        .includes(:external_identities)
        .where("external_identities.provider_id" => saml_provider.id,
               "external_identities.provider_type" => saml_provider.class.name)
        .references(:external_identities)
    else
      relation
    end
  end

  def external_identity_unlinked_clause(relation)
    if @query.external_identity_unlinked_scope? && saml_provider.present?
      users_with_linked_identity = ExternalIdentity.by_provider(saml_provider).distinct.pluck(:user_id).compact

      if users_with_linked_identity.empty?
        relation.includes(:external_identities)
      else
        relation
          .includes(:external_identities)
          .where("external_identities.provider_id IS NULL OR external_identities.user_id NOT IN (?)", users_with_linked_identity)
          .references(:external_identities)
      end
    else
      relation
    end
  end

  memoize def saml_provider
    @query.organization.external_identity_session_owner.saml_provider
  end

  # Public: Filter users based on organization membership entries to find users with derived membership.
  #
  # Derived membership in an EMU organization can be implied by the existence of organizatoin membership entry with
  # adder_type of 1, that is the user got organization membership by being added to an external group.
  # In this query, we get all the users who has organization entry with adder_type 1 by joining the user record with
  # organization_membership_entries record by user_id, organization_id and adder_type as an inner join.
  #
  # Returns: ActiveRecord::Relation of Users
  def organization_membership_group_clause(relation)
    if @query.organization_membership_group_scope?
      if OrganizationMembershipEntry.break_joins_enabled?
        user_ids = OrganizationMembershipEntry
          .where(organization_id: @query.organization.id, adder_type: 1)
          .pluck(:user_id)
        relation.where(id: user_ids).distinct
      else
        relation
          .joins("INNER JOIN organization_membership_entries ON users.id = organization_membership_entries.user_id AND organization_membership_entries.organization_id = #{@query.organization.id} AND organization_membership_entries.adder_type = 1")
          .distinct
      end
    else
      relation
    end
  end

  # Public: Filter users based on organization membership entries to find users with explicit membership.
  #
  # Explicit membership in an EMU organization can be implied by the existence of organizatoin membership entry with
  # adder_type of 0, that is the user got organization membership by being added by the admin.
  # In this query, we get all the users who has organization entry with adder_type 0 by joining the user record with
  # organization_membership_entries record by user_id, organization_id and adder_type as an inner join.
  #
  # Returns: ActiveRecord::Relation of Users
  def organization_membership_admin_clause(relation)
    if @query.organization_membership_admin_scope?
      if OrganizationMembershipEntry.break_joins_enabled?
        user_ids = OrganizationMembershipEntry
          .where(organization_id: @query.organization.id, adder_type: 0)
          .pluck(:user_id)
        relation.where(id: user_ids)
      else
        relation
          .joins("INNER JOIN organization_membership_entries ON users.id = organization_membership_entries.user_id AND organization_membership_entries.organization_id = #{@query.organization.id} AND organization_membership_entries.adder_type = 0")
      end
    else
      relation
    end
  end
end
