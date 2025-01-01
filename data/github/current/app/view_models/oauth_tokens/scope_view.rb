# typed: true
# frozen_string_literal: true

class OauthTokens::ScopeView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  attr_reader :scope

  DEPENDENT_SCOPES = {
    "repo" => ["write:packages", "workflow"],
    "read:packages" => ["write:packages", "delete:packages"]
  }

  RELATED_SCOPES = {
    "write:packages" => ["read:packages", "repo"],
    "delete:packages" => ["read:packages"],
    "workflow" => ["repo"],
  }

  # Some scopes require related scopes that are not nested. For example,
  # `repo` is required to published a package so we consider it related to
  # `write:packages`.
  #
  # Returns: [String]
  def related_scope_families(scope)
    RELATED_SCOPES.key?(scope) ? RELATED_SCOPES[scope] : []
  end

  def html_classes_for_scope(scope)
    return "js-checkbox-scope" unless scope.send(:parent).blank?
    "js-checkbox-scope parent-checkbox-scope"
  end

  def dependent_scope_selected?(scope, collection)
    selected_by(scope, collection).any?
  end

  def selected_by(scope, collection)
    Array(DEPENDENT_SCOPES[scope.name]) & collection
  end

  def child_scopes(user, scope)
    Api::AccessControl.child_scopes(scope)
  end
end
