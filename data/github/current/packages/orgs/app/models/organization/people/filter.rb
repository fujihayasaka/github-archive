# typed: true
# frozen_string_literal: true

# A class to encapsulate logic around chaining scopes based on filters expressed
# in the passed-in query object.
#
# Note: this intentionally does not scope users to a given organization. That
# should be handled separately when working with the scope returned from this
# class.
class Organization::People::Filter
  include GitHub::Memoizer

  def initialize(query:)
    @query = query
  end

  # Public: Build a scope of users based on the query object that gets passed
  # in. Apply clauses to the relation we build up based on the state of the
  # query object.
  #
  # Drawing a lot of inspiration from https://thoughtbot.com/blog/using-yieldself-for-composable-activerecord-relations
  #
  # Returns: ActiveRecord::Relation of Users
  def call
    User
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
      not_required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:optional, :exempt).values
      relation
        .includes(:two_factor_credential, :two_factor_requirement_metadata)
        .references(:two_factor_credential, :two_factor_requirement_metadata)
        .where("two_factor_credentials.id IS NULL")
        .where("two_factor_requirement_metadata.id IS NULL or two_factor_requirement_metadata.state IN (?)", not_required_states)
    else
      relation
    end
  end

  def two_factor_enabled_clause(relation)
    if @query.two_factor_enabled_scope?
      relation
        .includes(:two_factor_credential)
        .where("two_factor_credentials.id IS NOT NULL")
        .references(:two_factor_credential)
    else
      relation
    end
  end

  def two_factor_required_clause(relation)
    if @query.two_factor_required_scope?
      required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:required, :warning, :interrupt).values
      relation
        .includes(:two_factor_credential, :two_factor_requirement_metadata)
        .references(:two_factor_credential, :two_factor_requirement_metadata)
        .where("two_factor_credentials.id IS NULL")
        .where("two_factor_requirement_metadata.state IN (?)", required_states)
    else
      relation
    end
  end

  def two_factor_secure_clause(relation)
    if @query.two_factor_secure_scope?
      relation.two_factor_enabled.without_insecure_two_factor_methods
    else
      relation
    end
  end

  def two_factor_insecure_clause(relation)
    if @query.two_factor_insecure_scope?
      relation.two_factor_enabled.with_insecure_two_factor_methods
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
      relation
        .joins("INNER JOIN organization_membership_entries ON users.id = organization_membership_entries.user_id AND organization_membership_entries.organization_id = #{@query.organization.id} AND organization_membership_entries.adder_type = 1")
        .distinct
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
      relation
        .joins("INNER JOIN organization_membership_entries ON users.id = organization_membership_entries.user_id AND organization_membership_entries.organization_id = #{@query.organization.id} AND organization_membership_entries.adder_type = 0")
    else
      relation
    end
  end
end
