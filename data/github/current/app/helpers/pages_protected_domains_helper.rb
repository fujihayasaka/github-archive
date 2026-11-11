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
end
