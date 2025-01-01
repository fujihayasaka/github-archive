# typed: true
# frozen_string_literal: true

class Settings::AuditLog::SuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :filter, :cap_filter

  def actions
    AuditLogEntry.user_action_names
  end

  def repositories
    scope = current_user.visible_repositories_for(current_user)

    if filter.blank?
      scope = scope.recently_updated
    else
      scope = scope.where("name LIKE :filter OR owner_login LIKE :filter", { filter: "#{ActiveRecord::Base.sanitize_sql_like(filter)}%" })
    end
    scope = scope.distinct.limit(20).sort { |a, b| a.name_with_display_owner <=> b.name_with_display_owner }
    @repositories = cap_filter.authorized_resources(scope)
  end
end
