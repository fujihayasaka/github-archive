# typed: false
# frozen_string_literal: true

module Platform
  module Helpers
    module AchievementUnlockingEvent
      # Public: Return a Promise that resolves to the unlocking model of an Achievement object, if it is present and
      # the current API user has permission and scopes to see it.
      #
      # achievement - Achievement object to get the unlocking model of.
      #
      # Returns a Promise that resolves to an ActiveRecord model in Unions::UnlockingModel or nil.
      def async_visible_unlocking_model_from(achievement)
        Promise.all([
          achievement.async_unlocking_model,
          achievement.async_batch_unlocking_model_owner_opted_out?,
        ]).then do |(unlocking_model, opted_out)|
          next nil if unlocking_model.nil? || opted_out

          # Interior filtering within AchievementRepositoryList models, or other compound unlocking models that we
          # introduce in the future.
          if unlocking_model.respond_to?(:filter_promise)
            unlocking_model.filter_promise do |model|
              # Test API readability first. This accounts for repo privacy and membership as well as oauth token
              # scopes and such.
              graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(model)
              context[:permission].typed_can_see?(graphql_type_name, model).then do |can_see|
                next false unless can_see

                # Assumption: these are all Repositories. If they aren't, this will (safely) filter out everything,
                # and annoy someone enough so it gets fixed :-)
                next false unless model.respond_to?(:public) && model.respond_to?(:async_owner)

                # Public repos are always visible, so short-circuit here.
                next true if model.public?

                # Otherwise, test the owner opt-out flag.
                model.async_owner.then do |owner|
                  owner.profile.async_all_private_projects_opted_out_of_achievements_tracking?.then do |opted_out|
                    !opted_out
                  end
                end
              end
            end
          else
            graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(unlocking_model)
            context[:permission].typed_can_see?(graphql_type_name, unlocking_model).then do |can_see|
              unlocking_model if can_see
            end
          end
        end
      end
    end
  end
end
