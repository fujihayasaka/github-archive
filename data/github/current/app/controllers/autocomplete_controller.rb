# typed: true
# frozen_string_literal: true

class AutocompleteController < ApplicationController
  include OrganizationsHelper

  # Because this controller doesn't deal with protected organization resources,
  # we can safely `skip_before_action` its actions.
  # cap_bypass: needs a closer look, to evaluate if the skipped actions need to add CAP filters for the returned results
  skip_before_action :perform_conditional_access_checks, # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    only: [:users, :organizations, :user_suggestions, :organization_suggestions, :emoji_suggestions]

  before_action :login_required
  before_action :require_xhr, only: [:user_suggestions, :organization_suggestions, :emoji_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:users]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:organizations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:emoji_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:emojis_for_editor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:user_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:organization_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:org_users]

  def users # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      view = create_view_model(AutocompleteView, query: params[:q])
      visible_suggestions = cap_filter.authorized_resources(view.suggestions)
      format.html_fragment do
        render partial: "users/autocomplete", formats: :html, locals: {
          view: view,
          suggestions: visible_suggestions
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "users/autocomplete", locals: {
          view: view,
          suggestions: visible_suggestions
        }
      end
    end
  end

  def organizations # rubocop:todo GitHub/UseRestfulActions
    organizations = ::Organization.search(params[:q], limit: 10)
    visible_organizations = cap_filter.authorized_resources(organizations)
    respond_to do |format|
      format.html_fragment do
        render partial: "organizations/autocomplete", formats: :html, locals: {
          results: visible_organizations
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "organizations/autocomplete", locals: {
          results: visible_organizations
        }
      end
    end
  end

  def org_users # rubocop:todo GitHub/UseRestfulActions
    render_404 and return unless current_organization
    respond_to do |format|
      view = create_view_model(AutocompleteView, { query: params[:q], organization: current_organization, org_members_only: true })
      format.html_fragment do
        render partial: "users/autocomplete", formats: :html, locals: {
          view: view,
          suggestions: view.suggestions
        }
      end
      format.html do
        return head :not_acceptable unless request.xhr?
        render partial: "users/autocomplete", locals: {
          view: view,
          suggestions: view.suggestions
        }
      end
    end
  end

  def user_suggestions # rubocop:todo GitHub/UseRestfulActions
    suggester = Suggester::UserSuggester.new(viewer: current_user, cap_filter: cap_filter)
    respond_to do |format|
      format.json do
        render json: suggester.mentions
      end
    end
  end

  def organization_suggestions # rubocop:todo GitHub/UseRestfulActions
    suggester = Suggester::OrganizationSuggester.new(viewer: current_user, cap_filter: cap_filter)
    respond_to do |format|
      format.json do
        render json: suggester.mentions
      end
    end
  end

  def emoji_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "comments/suggesters/emoji_suggester", locals: {
          emojis: GitHub::Emoji,
          use_colon_emoji: params[:use_colon_emoji].present?,
          tone: logged_in? ? current_user.profile_settings.preferred_emoji_skin_tone : 0,
        }
      end
    end
  end

  def emojis_for_editor # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: GitHub::Emoji.for_editor
      end
    end
  end

  private

  def current_organization
    super || (
      if id = org_login_param || params[:id]
        if logged_in?
          org = Organization.find_by_login(id)
          return org if org && org.user_is_outside_collaborator?(current_user.id)
        end
      end
    )
  end
end
