# typed: strict
# frozen_string_literal: true

class Organization::BillingManagement
  extend T::Sig

  include Ability::Subject
  include Ability::Membership

  sig { params(organization: Organization).void }
  def initialize(organization)
    @organization = organization
  end

  sig { params(user: User, actor: T.nilable(User), invitation: T.nilable(OrganizationInvitation)).void }
  def add_manager(user, actor:, invitation: nil)
    grant user, :write

    instrument_options = { user: user, actor: actor }
    instrument_options[:invitation_email] = invitation.email if invitation && invitation.email?
    @organization.instrument :add_billing_manager, instrument_options

    GitHub.dogstats.increment("billing.managers.count", tags: ["action:add"])
  end

  sig { params(user: User, actor: T.nilable(User), reason: T.nilable(T.any(String, Symbol))).void }
  def remove_manager(user, actor:, reason: nil)
    return unless manager?(user)

    revoke user

    if @organization.saml_sso_enabled?
      ExternalIdentity.unlink_saml_identities(provider: @organization.saml_provider,
                                              user_ids: [user.id])
    end
    business = @organization.business
    if business && business.saml_sso_enabled?
      business.remove_user_from_business(user)
    end

    if user.has_trade_screening_record_linked_to_org?(organization: @organization)
      user.unlink_trade_screening_record_from_org(organization: @organization)
    end

    @organization.instrument :remove_billing_manager,
      user: user,
      actor: actor,
      reason: reason
    GitHub.dogstats.increment("billing.managers.count", tags: ["action:remove"])
  end

  sig { returns(T.nilable(Integer)) }
  def ability_id
    @organization.id
  end

  # Returns true if the given user is a billing manager of this organization.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def manager?(user)
    permit?(user, :write)
  end

  # Returns a Promise resolving to true if the given user is a billing manager of this organization.
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_manager?(user)
    async_permit?(user, :write)
  end

  # Internal: remove all billing managers, used when destroying an organization
  sig { void }
  def remove_all_managers
    members.each do |manager|
      remove_manager manager, actor: nil
    end
  end

  # Internal: See Ability::Subject#grant?
  sig { params(actor: User, action: Symbol).returns(T::Boolean) }
  def grant?(actor, action)
    @organization.grant?(actor, action)
  end

  sig { returns(Organization) }
  def target_for_conditional_access
    @organization
  end
end
