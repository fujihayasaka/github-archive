# typed: true
# frozen_string_literal: true

class DiscoverPeopleController < ApplicationController
  before_action :login_required, :require_feature_to_be_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "discover_people/index", locals: {
      popular_developers: popular_developers
    }
  end

  private

  # Private: List of popular developers.
  #
  # Returns an Array of ExploreFeed::Trending::Developer objects.
  def popular_developers
    developers = ExploreFeed::Trending::Developer.all(
      period: "monthly",
      limit: 24
    )

    developers = developers.reject do |developer|
      developer.most_popular_repository.nil?
    end

    # Preload associations
    users = developers.map(&:original_user)
    GitHub::PrefillAssociations.prefill_associations(users, :profile)
    GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, current_user)

    developers
  end

  def require_feature_to_be_enabled
    render_404 unless discover_people_enabled?
  end

  def discover_people_enabled?
    !GitHub.enterprise? && user_feature_enabled?(:feed_discover_people)
  end

  def resource_for_conditional_access
    # cap_bypass: accessing other users, but using current_user
    return :no_resource_for_conditional_access unless logged_in? # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
