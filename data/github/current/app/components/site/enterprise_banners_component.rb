# typed: true
# frozen_string_literal: true

module Site
  # This gets all banners that should be displayed for the current page.
  # TODO This desperately needs optimization before being used in production.
  class EnterpriseBannersComponent < ApplicationComponent
    include UrlHelpers
    include BusinessesHelper
    include ResilienceHelper

    def render?
      return false if !logged_in?

      banner_levels_to_display.any?
    end

    def banners
      shown_banners = with_database_error_fallback(fallback: []) do
        banners = EnterpriseBanner.active.where(owner: banner_levels_to_display)
        dismissed_banners = logged_in? ? EnterpriseBannerDismissal.where(enterprise_banner: banners, user: current_user) : []

        banners.select { |banner| !dismissed_banners.map(&:enterprise_banner).include?(banner) }
      end
      sorted_banners = []

      # sort banners so repo is always first, then org, then enterprise
      if repo_level_banner_ff_enabled && repo_banner = shown_banners.find { |sb| sb.owner_type == "Repository" }
        sorted_banners << repo_banner
      end

      if org_banner = shown_banners.find { |sb| sb.owner_type == "User" }
        sorted_banners << org_banner
      end

      if enterprise_banner = shown_banners.find { |sb| sb.owner_type == "Business" }
        sorted_banners << enterprise_banner
      end

      sorted_banners.map do |banner|
        html_message = GitHub::Goomba::EnterpriseAnnouncementPipeline.to_html(banner.message, cache_settings: { use_cache: true })
        { text: html_message, owner: banner.owner, dismissible: banner.dismissible, id: banner.id, date: banner.updated_at }
      end
    end

    private

    # this method is hit *a lot*, so the logic is purposely a bit verbose to avoid extra DB queries
    memoize def banner_levels_to_display
      if !current_repository.nil?
        # return immediately if the repo isn't in a business, no need to check anything else
        return [] if repo_business.nil?

        # current_repository.outside_collaborator_ids calls the same thing as this under the hood, but it does an
        # additional query to remove any org members and only return actual outside collaborators. we don't need that
        # special behavior here, so calling direct_member_ids is fine
        collaborator_ids = current_repository.direct_member_ids if repo_level_banner_ff_enabled

        # if collaborator_ids is empty (no outside collaborators) plus the user isn't in a business,
        # then there's no need to continue
        return [] if repo_level_banner_ff_enabled && collaborator_ids.empty? && current_user_business_ids.empty?

        user_is_collaborator = collaborator_ids.include?(current_user.id) if repo_level_banner_ff_enabled
        user_is_business_member = current_user_business_ids.include?(repo_business.id)

        # a user may be both a member and an outside collaborator
        user_is_only_outside_collaborator = user_is_collaborator && !user_is_business_member

        # we only want to show the repo-level banner to outside collaborators, not the org- or enterprise-level
        # banners, so return early if this is the case
        return [current_repository] if user_is_only_outside_collaborator

        repository = current_repository if user_is_business_member
      end

      # if repository isn't nil and the user isn't a collaborator, then we already know that the org it's in is in a
      # business that the user is a member of (since repo.business comes from the org membership in the first place).
      if !repository.nil? && !user_is_only_outside_collaborator
        organization = repository.organization
      else
        organization = current_organization if !current_organization&.business.nil? && current_user_business_ids.include?(current_organization.business.id)
      end

      # likewise, if organization isn't nil, then the check can be bypassed for the enterprise
      if !organization.nil? && !user_is_only_outside_collaborator
        # repo_business may already be memoized, so potentially save some DB queries
        enterprise = repo_business || organization.business
      else
        enterprise = memoized_current_business if !memoized_current_business.nil? && current_user_business_ids.include?(memoized_current_business.id)
      end

      [repository, organization, enterprise].compact
    end

    memoize def current_user_business_ids
      current_user.businesses(membership_type: :org_membership).pluck(:id)
    end

    memoize def repo_business
      current_repository&.owner&.async_business&.sync
    end

    memoize def memoized_current_business
      current_business
    end

    # business to use when checking if FFs are enabled
    memoize def ff_business
      repo_business || memoized_current_business
    end

    memoize def repo_level_banner_ff_enabled
      GitHub.flipper[:enterprise_banners_repo_level].enabled?(ff_business)
    end
  end
end
