# typed: strict
# frozen_string_literal: true

class Sponsors::Orgs::YourSponsorshipsComponent < ApplicationComponent
  # For the data structs, `nil` is used to indicate that the data should be omitted from the payload,
  # which is achieved by calling T::Struct#serialize. This is done to limit payload size.

  class SponsorshipData < T::Struct
    const :id, String
    const :sponsorableLogin, String
    const :sponsorableIsOrg, T::Boolean
    const :sponsorableAvatarUrl, String
    const :active, T::Boolean
    const :startDate, String
    const :viewerIsSponsor, T.nilable(T::Boolean)
    # member data
    const :privacyLevel, T.nilable(String)
    # admin data
    const :amount, T.nilable(String)
    const :pendingChange, T.nilable(String)
    const :subscribableId, T.nilable(Integer)
    const :patreonLink, T.nilable(String)
    const :subscribedToNewsletterUpdates, T.nilable(T::Boolean)
  end

  class ReactProps < T::Struct
    const :sponsorLogin, String
    const :viewerPrimaryEmail, T.nilable(String)
    const :viewerIsOrgMember, T::Boolean
    const :viewerCanManageSponsorships, T::Boolean
    const :sponsorships, T::Array[SponsorshipData]
  end

  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      viewer: T.nilable(User),
      viewer_is_org_member: T::Boolean,
      viewer_can_manage_sponsorships: T::Boolean,
    ).void
  end
  def initialize(sponsor:, viewer:, viewer_is_org_member:, viewer_can_manage_sponsorships:)
    @sponsor = sponsor
    @viewer = viewer
    @viewer_is_org_member = viewer_is_org_member
    @viewer_can_manage_sponsorships = viewer_can_manage_sponsorships
  end

  delegate :render_react_partial, to: :helpers

  sig { returns(String) }
  def call
    content_tag(:div, **test_selector_data_hash("your-sponsorships-react-partial")) do
      render_react_partial(
        name: "your-sponsorships",
        props: react_partial_props,
        ssr: false
      )
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def react_partial_props
    ReactProps.new(
      sponsorLogin: @sponsor.login,
      viewerPrimaryEmail: require_admin_viewer { @viewer&.email },
      viewerIsOrgMember: @viewer_is_org_member,
      viewerCanManageSponsorships: @viewer_can_manage_sponsorships,
      sponsorships: serialized_sponsorships,
    ).serialize
  end

  private

  sig do
    type_parameters(:T)
      .params(
        blk: T.proc.returns(T.type_parameter(:T))
      )
      .returns(T.nilable(T.type_parameter(:T)))
  end
  def require_admin_viewer(&blk)
    return nil unless @viewer_can_manage_sponsorships
    yield
  end

  sig do
    type_parameters(:T)
      .params(
        blk: T.proc.returns(T.type_parameter(:T))
      )
      .returns(T.nilable(T.type_parameter(:T)))
  end
  def require_member_viewer(&blk)
    return nil unless @viewer_is_org_member
    yield
  end

  sig do
    type_parameters(:T)
      .params(
        blk: T.proc.returns(T.type_parameter(:T))
      )
      .returns(T.nilable(T.type_parameter(:T)))
  end
  def require_non_admin_viewer(&blk)
    return nil unless @viewer.present?
    return nil if @viewer_can_manage_sponsorships
    yield
  end

  sig { returns T::Array[SponsorshipData] }
  def serialized_sponsorships
    scope = @sponsor.sponsorships_as_sponsor
      .includes(:tier, :sponsor, :sponsorable)
    scope = scope.privacy_public unless @viewer_can_manage_sponsorships || @viewer_is_org_member
    sponsorships = scope.to_a
    # Patreon and pending changes are the most expensive associations to load, so we load the relevant subset
    sponsorships.filter_map { |s| s.sponsorable if s.active? && s.patreon? }.then do |active_patreon_sponsorables|
      GitHub::PrefillAssociations.prefill_associations(
        active_patreon_sponsorables,
        { sponsors_patreon_user: :sponsors_patreon_tiers }
      )
    end
    sponsorships.select { |s| s.active? && s.github? }.then do |active_github_sponsorships|
      GitHub::PrefillAssociations.prefill_batch_method(
        active_github_sponsorships,
        :pending_change
      )
    end
    serialized_sponsorships = sponsorships.map { |sponsorship| serialize_sponsorship(sponsorship: sponsorship) }
  end

  sig { returns(T::Set[Integer]) }
  memoize def viewer_active_sponsorable_ids
    sponsorable_ids = @viewer&.active_sponsorships_as_sponsor_relation&.map(&:sponsorable_id) || []
    Set.new(sponsorable_ids)
  end

  sig { params(sponsorship: Sponsorship).returns(T.nilable(String)) }
  def patreon_membership_link(sponsorship:)
    return unless sponsorship.active? && sponsorship.patreon?
    sponsorship.sponsorable&.sponsors_patreon_membership_link
  end

  sig { params(sponsorship: Sponsorship).returns(String) }
  def start_date_text(sponsorship:)
    start_date_formatted = sponsorship.tier_selected_date.strftime("%b %e, %Y")
    expiration_datetime = sponsorship.active? && sponsorship.expires_at
    start_date_text = if @viewer_can_manage_sponsorships && expiration_datetime.present?
      end_date_formatted = expiration_datetime.strftime("%b %e, %Y")
      "#{start_date_formatted} (expires #{end_date_formatted})"
    else
      start_date_formatted
    end
  end

  sig { params(sponsorship: Sponsorship).returns(T.nilable(String)) }
  def pending_change_text(sponsorship:)
    return unless sponsorship.github? && sponsorship.active?
    pending_change = T.let(sponsorship.pending_change, T.nilable(Sponsorship::PendingChange))
    return unless pending_change
    pending_change.to_s
  end

  sig { params(sponsorship: Sponsorship).returns(SponsorshipData) }
  def serialize_sponsorship(sponsorship:)
    sponsorable = sponsorship.sponsorable

    SponsorshipData.new(
      id: sponsorship.id.to_s,
      sponsorableLogin: sponsorable&.login || "unknown",
      sponsorableIsOrg: sponsorable&.organization? || false,
      sponsorableAvatarUrl: sponsorable&.primary_avatar_url || "",
      active: sponsorship.active?,
      startDate: start_date_text(sponsorship: sponsorship),
      viewerIsSponsor: require_non_admin_viewer { viewer_active_sponsorable_ids.include?(sponsorship.sponsorable_id) },
      privacyLevel: require_member_viewer { sponsorship.privacy_level },
      amount: require_admin_viewer { sponsorship.amount_per_cycle },
      pendingChange: require_admin_viewer { pending_change_text(sponsorship: sponsorship) },
      subscribableId: require_admin_viewer { sponsorship.subscribable_id },
      patreonLink: require_admin_viewer { patreon_membership_link(sponsorship: sponsorship) },
      subscribedToNewsletterUpdates: require_admin_viewer { sponsorship.is_sponsor_opted_in_to_email? },
    )
  end
end
