# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class MetadataComponent < ApplicationComponent
      COLUMN_COMMENT_OVERRIDES = {
        "achievements" => "This will target all achievement related attributes.",
        "stars_count" => "Includes starred repositories and topics.",
      }
      CUSTOM_COLUMNS = %w(achievements)
      HIDDEN_ATTRIBUTES_LIST = %w(
        achievement_private_slugs
        achievement_public_slugs
        achievements_private_count
        achievements_public_count
        created_at
        has_unseen_private_achievement
        has_unseen_public_achievement
        id
        updated_at
        user_id
      ).freeze

      def initialize(user:)
        @user = user
      end

      private

      attr_reader :user
      delegate :current_repository, to: :helpers

      memoize def user_metadata
        user.metadata
      end

      def metadata_persisted?
        user_metadata.persisted?
      end

      def metadata_attributes
        custom_columns_and_values = CUSTOM_COLUMNS.map { |column| [column, nil] }.to_h
        user_metadata.attributes.except(*HIDDEN_ATTRIBUTES_LIST).merge(custom_columns_and_values)
      end

      def display_value_for(value)
        if attribute_is_count?(value)
          value
        elsif attribute_is_boolean?(value)
          if value
            primer_octicon(:check, color: :success)
          else
            primer_octicon(:x, color: :danger)
          end
        end
      end

      # Private: Get a column comment if one exists for the given column name (String)
      #
      # Returns a String or nil
      def column_comment_for(column_name)
        COLUMN_COMMENT_OVERRIDES[column_name] ||
          UserMetadata.columns_hash[column_name]&.comment
      end

      def attribute_is_count?(value)
        value.is_a?(Integer)
      end

      def attribute_is_boolean?(value)
        value.is_a?(TrueClass) || value.is_a?(FalseClass)
      end

      def attribute_update_path(attribute, value)
        if attribute_is_boolean?(value)
          toggle_attribute_stafftools_user_profile_path(user, attribute: attribute)
        else
          recalculate_attribute_stafftools_user_profile_path(user, attribute: attribute)
        end
      end

      def attribute_update_button_text(value)
        if attribute_is_boolean?(value)
          "Toggle"
        else
          "Recalculate"
        end
      end
    end
  end
end
