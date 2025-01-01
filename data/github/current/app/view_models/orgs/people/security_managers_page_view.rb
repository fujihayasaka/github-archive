# typed: true
# frozen_string_literal: true

class Orgs::People::SecurityManagersPageView < Orgs::OverviewView
  SECURITY_MANAGERS_PER_PAGE = 30

  attr_reader :organization, :page, :query, :role

  def page_title
    "Security Managers for · #{organization.safe_profile_name}"
  end

  def security_managers
    @security_managers ||= found_security_managers.paginate(page: page, per_page: SECURITY_MANAGERS_PER_PAGE)
  end

  def show_no_results?
    query.present? && !security_managers_present?
  end

  def security_managers_present?
    security_managers.present?
  end

  def security_managers_count
    @security_managers_count ||= security_managers.count
  end

  def found_security_managers
    @found_security_managers = SecurityProduct::SecurityManagers.new(organization).users

    if query.present?
      q = query.strip.downcase
      @found_security_managers = @found_security_managers.select do |user|
        user.display_login.downcase.include?(q) || user.name&.downcase&.include?(q)
      end
    end
    @found_security_managers
  end
end
