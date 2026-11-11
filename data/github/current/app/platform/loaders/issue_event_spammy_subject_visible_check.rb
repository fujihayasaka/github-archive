# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueEventSpammySubjectVisibleCheck < Platform::Loader
      def self.load(viewer:, event_id:)
        self.for(viewer).load(event_id)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(event_ids)
        event_and_subject_ids = IssueEventDetail.where(
          issue_event_id: event_ids,
        ).pluck(:issue_event_id, :subject_id)

        subject_is_spammy = User.where(
          id: event_and_subject_ids.map(&:second),
        ).pluck(:id, :spammy).to_h

        event_and_subject_ids.each_with_object(Hash.new) do |value, hash|
          event_id = value[0]
          subject_id = value[1]

          # spammy users can always see their own content
          viewer_is_subject = @viewer&.id == subject_id
          # site admins are exempt from spammy filters
          viewer_is_site_admin = @viewer&.site_admin?

          is_visible = if viewer_is_subject || viewer_is_site_admin
            true
          else
            !subject_is_spammy[subject_id]
          end

          hash[event_id] = is_visible
        end
      end
    end
  end
end
