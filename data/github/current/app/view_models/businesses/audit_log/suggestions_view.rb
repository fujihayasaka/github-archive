# typed: true
# frozen_string_literal: true

class Businesses::AuditLog::SuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business
  attr_reader :filter

  def actions
    if business.enterprise_managed_user_enabled?
      AuditLogEntry.enterprise_managed_user_action_names
    else
      AuditLogEntry.business_action_names
    end.reject { |a| a.start_with?("git.") }
  end

  def users
    scope = business.visible_organization_members_for(current_user)
    unless filter.blank?
      scope = scope.where("login LIKE :filter", { filter: "#{ActiveRecord::Base.sanitize_sql_like(filter)}%" })
    end

    @users = scope.limit(20).order("login")
  end

  def organizations
    scope = business.organizations_for_member(current_user)
    unless filter.blank?
      scope = scope.where("login LIKE :filter", { filter: "#{ActiveRecord::Base.sanitize_sql_like(filter)}%" })
    end

    @organizations = scope.limit(20).order("login")
  end
end
