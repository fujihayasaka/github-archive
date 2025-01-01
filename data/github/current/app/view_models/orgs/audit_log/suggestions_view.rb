# typed: true
# frozen_string_literal: true

class Orgs::AuditLog::SuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :filter

  def actions
    AuditLogEntry.organization_action_names.reject { |a| a.start_with?("git.") }
  end

  def users
    scope = organization.visible_users_for(current_user)
    unless filter.blank?
      scope = scope.where("login LIKE :filter", { filter: "#{ActiveRecord::Base.sanitize_sql_like(filter)}%" })
    end
    @users = scope.limit(20).order("login")
  end

  def repositories
    scope = organization.visible_repositories_for(current_user)
    if filter.blank?
      scope = scope.recently_updated
    else
      scope = scope.where("name LIKE :filter OR owner_login LIKE :filter", { filter: "#{ActiveRecord::Base.sanitize_sql_like(filter)}%" })
    end
    @repositories = scope.distinct.limit(20).sort { |a, b| a.name_with_display_owner <=> b.name_with_display_owner }
  end
end
