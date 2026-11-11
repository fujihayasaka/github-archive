# typed: true
# frozen_string_literal: true

# A user's dashboard. Represents a Homescreen, or Homepage.
class UserDashboard < ApplicationRecord::Collab
  include GitHub::Prioritizable::Context
  include GitHub::Tracing

  belongs_to :user

  has_many :shortcuts,
    -> { merge(SearchShortcut.by_priority) },
    class_name: "SearchShortcut",
    foreign_key: :dashboard_id,
    inverse_of: :dashboard,
    dependent: :destroy

  has_many :saved_collections,
    class_name: "Dashboard::SavedCollection",
    foreign_key: :dashboard_id,
    inverse_of: :dashboard,
    dependent: :destroy

  prioritizes :shortcuts, with: :shortcuts, inverse_of: :dashboard

  validates :user, presence: true, uniqueness: true

  has_many :user_dashboard_teams, class_name: "UserDashboardTeam", dependent: :destroy
  has_many :selected_teams, class_name: "Team", through: :user_dashboard_teams, source: :team, disable_joins: true
  validates_length_of :selected_teams,  maximum: 100, message: "can't have more than 100 teams"
  validate :user_can_see_select_teams

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }

  def user_can_see_select_teams
    selected_teams.each do |team|
      if !team.visible_to?(user)
        errors.add :selected_teams, "user must be able to view all selected teams"
        return
      end
    end
  end

  def mobile_nav_links
    ::Mobile::HomeNavLink.all_for_user(user)
  end

  def async_mobile_nav_links
    ::Mobile::HomeNavLink.async_all_for_user(user)
  end

  def update_mobile_nav_links!(sorted_links:, hidden_links:)
    ::Mobile::HomeNavLink.update_for_user!(
      user,
      sorted_links: sorted_links,
      hidden_links: hidden_links
    )
  end

  def async_saved_collections(order_by: {})
    order_by_field = order_by.dig(:field) || "created_at"
    order_by_direction = order_by.dig(:direction) || "DESC"
    Promise.resolve(saved_collections.order("saved_collections.#{order_by_field} #{order_by_direction}"))
  end

  def async_reviews_collection
    Promise.resolve(saved_collections.find_by(protected_type: Dashboard::SavedCollection.protected_types[:reviews]))
  end
end
