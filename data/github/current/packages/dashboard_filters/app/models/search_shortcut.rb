# typed: true
# frozen_string_literal: true

class SearchShortcut < ApplicationRecord::Collab
  include GitHub::UTF8
  include GitHub::Prioritizable
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include Instrumentation::Model
  include SearchDisplayable
  include SearchPriorityHelper
  include SearchQueryable
  include Repositories::BelongsToRepository

  MAX_PER_DASHBOARD = 25

  validates :dashboard, presence: true

  belongs_to :dashboard,
    class_name: "UserDashboard",
    foreign_key: :dashboard_id,
    inverse_of: :shortcuts

  belongs_to_repository_via_domain relation_name: :scoping_repository,
    foreign_key: :scoping_repository_id,
    class_name: "Repository",
    feature_flag: "repos_domain_associations"

  delegate :user, :async_user, to: :dashboard

  validate :dashboard_user_has_less_than_max_shortcuts, on: :create
  validate :dashboard_user_can_view_scoping_repository, on: :create
  validates :priority, uniqueness: { scope: :dashboard_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true
    }

  after_create_commit :instrument_create
  before_destroy :instrument_destroy


  def self.instrument_create(search_type:, user:, scoping_repository_id:, shortcut_id: nil, context: nil)
    GlobalInstrumenter.instrument("user_dashboard_shortcut.create", {
      scoping_repository_id: scoping_repository_id,
      user: user,
      search_type: search_type,
      shortcut_id: shortcut_id,
      context: context,
    })
  end

  def self.instrument_destroy(search_type:, user:, scoping_repository_id:, context: nil)
    GlobalInstrumenter.instrument("user_dashboard_shortcut.destroy", {
      scoping_repository_id: scoping_repository_id,
      user: user,
      search_type: search_type,
      context: context,
    })
  end

  private

  def dashboard_user_has_less_than_max_shortcuts
    if self.class.where(dashboard_id: dashboard_id).count >= MAX_PER_DASHBOARD
      errors.add(:base, "cannot have more than #{MAX_PER_DASHBOARD} shortcuts")
    end
  end

  def dashboard_user_can_view_scoping_repository
    scoping_repo = T.cast(scoping_repository, T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    if scoping_repo && !scoping_repo.readable_by?(user)
      errors.add(:scoping_repository, :not_found, message: "not found for dashboard owner")
    end
  end

  def instrument_create
    self.class.instrument_create(
      search_type: search_type,
      user: user,
      scoping_repository_id: scoping_repository_id,
      shortcut_id: self.id,
      context: "web",
    )
  end

  def instrument_destroy
    self.class.instrument_destroy(
      search_type: search_type,
      user: user,
      scoping_repository_id: scoping_repository_id,
      context: "web",
    )
  end
end
