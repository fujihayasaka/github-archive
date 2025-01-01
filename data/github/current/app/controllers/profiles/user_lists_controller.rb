# typed: true
# frozen_string_literal: true

module Profiles
  class UserListsController < ApplicationController
    include ProfilesHelper
    include UserContributionsHelper

    before_action :ensure_profile_visible

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      only: [:index]

    def index
      sorting_strategy = UserLists::SortingStrategy.new(params[:user_lists_sort], params[:user_lists_direction])

      if logged_in?
        ActiveRecord::Base.connected_to(role: :writing) do
          current_user.settings.set!(:user_profile_lists_sorting_strategy, sorting_strategy.serialize)
        end
      end

      user_lists = UserLists::ListCollection.new(
        this_user.lists,
        sorting_strategy: sorting_strategy,
        owner: this_user
      )

      render UserLists::ProfileListsComponent.new(user_lists: user_lists), layout: false
    end

    private

    def resource_for_conditional_access
      :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    end

    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
