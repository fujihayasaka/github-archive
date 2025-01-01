# typed: strict
# frozen_string_literal: true

class Repositories::FundingLinks::ListComponent < ApplicationComponent
  extend T::Sig

  # repository - the repo the funding links are being displayed for
  # previewing - whether the funding links are being previewed
  sig do
    params(funding_links: T.nilable(FundingLinks), repository: T.nilable(Repository), previewing: T::Boolean).void
  end
  def initialize(funding_links:, repository:, previewing: false)
    @funding_links = funding_links
    @repository = repository
    @previewing = previewing
  end

  private

  sig { returns T::Boolean }
  def render?
    !!(@repository.present? && @funding_links.present? && funding_links.has_valid_platform?)
  end

  sig { returns FundingLinks }
  def funding_links
    T.must_because(@funding_links) { "#render? ensures non-nil" }
  end

  sig { returns Repository }
  def repository
    T.must_because(@repository) { "#render? ensures non-nil" }
  end

  sig { returns T::Boolean }
  def previewing?
    @previewing
  end

  sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
  memoize def external_accounts
    funding_links.external_funding_accounts
  end

  sig { returns T.nilable(Organization) }
  def sponsorable_org
    all_sponsorables_by_type[:org]
  end

  sig { returns T::Array[User] }
  memoize def sponsorable_users
    all_sponsorables_by_type[:users]
  end

  sig { returns({ users: T::Array[User], org: T.nilable(Organization) }) }
  memoize def all_sponsorables_by_type
    org = funding_links.sponsorable_org

    users = funding_links.sponsorable_users
    org_and_users = [org].compact + users
    GitHub::PrefillAssociations.prefill_associations(org_and_users, :sponsors_listing)
    GitHub::PrefillAssociations.prefill_batch_method(org_and_users, :sponsored_by_viewer?, current_user)
    GitHub::PrefillAssociations.prefill_batch_method(org_and_users, :async_sponsorable_by?, current_user)

    { users: users, org: org }
  end
end
