# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class AvatarsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user
      attr_reader :filtered_avatar_id

      def page_title
        "#{user.login} - Avatars"
      end

      def primary_avatar
        load_avatars if @primary_avatar.nil?
        @primary_avatar || nil
      end

      def avatars
        load_avatars if @avatars.nil?
        @avatars
      end

      def previous_avatar
        load_avatars if @avatars.nil?
        @previous_avatar ||= primary_avatar && avatars.detect { |a| a.id == user.primary_avatar.previous_avatar_id }
      end

      def undoable?
        user.primary_avatar.previous_avatar_id
      end

      def filtered_avatar?(avatar)
        filtered_avatar_id.to_i > 0 && avatar.avatar_id != filtered_avatar_id
      end

      def storage_blob_url(avatar)
        if GitHub.storage_cluster_enabled?
          urls.stafftools_storage_blob_path(avatar.oid)
        else
          urls.stafftools_asset_path(avatar.oid)
        end
      end

      private

      def load_avatars
        filtered_avatar_id.to_i == 0 ? load_all_avatars : load_filtered_avatars
      end

      # loads recent avatars and the current primary
      def load_all_avatars
        primary, avatars = user.all_avatars
        @primary_avatar = primary || false
        @avatars = avatars
        GitHub::PrefillAssociations.prefill_associations(avatars, [:asset, :storage_blob])
      end

      # only displays the avatar matching the ?avatar_id param.
      # The chosen avatar should have the correct buttons and labels.
      def load_filtered_avatars
        primary = user.primary_avatar
        @primary_avatar = (primary && primary.avatar) || false
        @avatars = if @primary_avatar && @primary_avatar.id == filtered_avatar_id
          []
        else
          user.avatars.where(id: filtered_avatar_id).to_a
        end
      end
    end
  end
end
