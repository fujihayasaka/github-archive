# typed: strict
# frozen_string_literal: true

class Orgs::CodeQualityOptionsController < Orgs::Controller
  before_action :organization_read_required
  before_action :code_quality_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index]

  Suggestions = ::SecurityCenter::Suggestions::Orgs

  sig { void }
  def index
    return render_404 if invalid_options_type?

    json_suggestions = suggestions.map do |suggestion|
      {
        value: suggestion.value,
        displayName: suggestion.label,
        description: suggestion.description,
      }
    end

    render json: json_suggestions, layout: false
  end

  private

  sig { returns(String) }
  memoize def options_type
    params.fetch("options-type", "").downcase
  end

  sig { returns(T::Hash[String, Symbol]) }
  memoize def options_type_to_suggestions_method
    {
      "teams" => :team_suggestions,
      "topics" => :topic_suggestions,
      "props" => :custom_property_suggestions,
    }
  end

  sig { returns(T::Boolean) }
  memoize def invalid_options_type?
    !options_type_to_suggestions_method.key?(options_type)
  end

  sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
  memoize def suggestions
    return [] if invalid_options_type?
    send(T.must(options_type_to_suggestions_method[options_type])) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
  end

  sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
  memoize def team_suggestions
    Suggestions::Team.new(
      limit:,
      organization: this_organization,
      selected_values:,
      user: current_user,
      value:,
    ).suggestions
  end

  sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
  memoize def topic_suggestions
    Suggestions::Topic.new(
      allowed_repo_ids:,
      limit:,
      organization: this_organization,
      selected_values:,
      value:,
    ).suggestions
  end

  sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
  memoize def custom_property_suggestions
    Suggestions::CustomProperty.new(
      allowed_repo_ids:,
      limit:,
      organization: this_organization,
      name: params.fetch(:name, ""),
      selected_values:,
      value:,
    ).suggestions
  end

  sig { returns(T.nilable(Integer)) }
  memoize def limit
    params.fetch(:limit).to_i if params.key?(:limit)
  end

  sig { returns(String) }
  memoize def value
    params.fetch(:value, "")
  end

  sig { returns(T::Array[String]) }
  memoize def selected_values
    params[:selected_values].try(:split, ",") || []
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  def allowed_repo_ids
    CodeQuality::OrgAuthz.allowed_repo_ids(user: current_user, organization: this_organization).repository_ids
  end

  sig { void }
  def code_quality_required
    render_404 unless CodeQuality.available?(this_organization)
  end
end
