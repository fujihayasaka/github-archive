# typed: false
# frozen_string_literal: true

module PagesProtectedDomainsHelper

  # Public: Determine if domain protection is enabled for the provided user.
  #
  # user - User to check. It is an optional parameter since it will not be needed when this feature is
  #        enabled globally but will currently return false if not provided.
  #
  # Examples
  #   pages_domain_protection_enabled?(user: current_user) # => true
  #
  # Returns true only if domain protection is enabled for the provided user and false otherwise.
  def pages_domain_protection_enabled?(user: nil)
    return false unless user.present?
    GitHub.pages_domain_protection_enabled?
  end

  def current_pages_owner
    return @current_pages_owner if defined?(@current_pages_owner)

    @current_pages_owner = if params[:organization_id]
      org = Organization.find_by_login(params[:organization_id])
      if org&.adminable_by?(current_user)
        org
      end
    else
      current_user
    end

    @current_pages_owner
  end

  def time_until_unverification(unverified_at)
    # Time.zone.now is in the request's time zone, domain.unverified_at is in UTC
    duration = (unverified_at - Time.zone.now).seconds

    return nil if duration < 0

    days = duration.in_days.round
    return "#{days} days" if days > 1

    hours = duration.in_hours.round
    return "#{hours} hours" if hours > 1

    minutes = duration.in_minutes.round
    "#{minutes} #{"minute".pluralize(minutes)}"
  end

  def repositories_to_unpublish_if_deleted(protected_domain)
    owner = protected_domain.owner

    domain_verified_by_other = Page::ProtectedDomain
      .where(name: protected_domain.name, state: [:verified, :pending])
      .where.not(owner: owner)
      .exists?

    parent_domain_verified_by_other = Page::ProtectedDomain
      .where(name: protected_domain.parent_domain, state: [:verified, :pending])
      .where.not(owner: owner)
      .exists?

    return owner.repositories.none unless domain_verified_by_other || parent_domain_verified_by_other

    # If this domain OR the parent domain, is verified by another owner, pages published
    # on this domain name will be unpublished.
    query = owner.repositories
      .select("repositories.*, page.cname, page.parent_domain")
      .joins(:page)
      .where(page: { cname: protected_domain.name })

    # Additionally, if this domain is verified by another owner, pages published on a
    # subdomain of this domain will be unpublished.
    if domain_verified_by_other
      query.or(owner.repositories.joins(:page).where(page: { parent_domain: protected_domain.name }))
    else
      query
    end
  end
end
