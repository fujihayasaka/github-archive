# typed: strict
# frozen_string_literal: true

class Issues::MetadataSuggestionStaffbarComponent < ApplicationComponent
  sig { params(controller_name: String, action_name: String, issue: T.nilable(Issue), repository: T.nilable(Repository)).void }
  def initialize(controller_name:, action_name:, issue: nil, repository: nil)
    @controller_name = controller_name
    @action_name = action_name
    @issue = issue
    @repository = repository
  end

  sig { returns T.nilable(T::Boolean) }
  def render?
    logged_in? && (current_user.site_admin? || current_user.employee?) &&
      user_feature_enabled?(:copilot_auto_assign_metadata) &&
      user_feature_enabled?(:copilot_auto_assign_metadata_staffbar) &&
      (@controller_name == "issues" && @action_name == "show" ||
      @controller_name == "issues_fragments" && @action_name == "issue_layout")
  end

  private

  sig { returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def load_labels
    return [] unless @repository&.labels

    @repository.labels.strict_loading.map do |label|
      {
        name: label.name,
        description: label.description,
        color: label.color,
      }
    end
  end

  sig { returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def load_types
    return [] unless issue_types = @repository&.owner&.issue_types

    issue_types.strict_loading.map do |issue_type|
      {
        name: issue_type.name,
        description: issue_type.description,
      }
    end
  end


  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def create_props
    {
      repositoryLabels: load_labels,
      repositoryTypes: load_types,
      issueId: @issue&.id,
      issueTitle: @issue&.title,
      issueBody: @issue&.body,
    }
  end
end
