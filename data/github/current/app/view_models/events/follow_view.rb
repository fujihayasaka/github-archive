# typed: false
# frozen_string_literal: true

# Decorates a Stratocaster::Attributes::Follow event with view logic.
#
# Examples
#
#   # equivalent ways to render the event's html
#   render_event(Events::FollowView.new(event))
#
#   # or
#   render_event(Events::View.for(event))
module Events
  class FollowView < View
    def title_text
      parts = [actor_text, "started following", target_text]
      parts.join(" ")
    end

    def actor_followers_count
      return @actor_followers_count if defined?(@actor_followers_count)
      @actor_followers_count = if sender_record
        sender_record.followers_count(viewer: nil)
      end
    end

    def actor_public_repos_count
      return @actor_public_repos_count if defined?(@actor_public_repos_count)
      @actor_public_repos_count = if sender_record
        sender_record.repository_counts.public_repositories
      end
    end

    def actor_avatar_url
      if sender_record
        sender_record.primary_avatar_url(80)
      end
    end

    def show_event_details?(viewer:)
      # Always show user details in the view when the current user is the one who was followed,
      # since we'll show info about the actor instead of the target.
      viewer_is_followee?(viewer) || target_info_present?
    end

    # Public: Check if the user who was followed in this event is the same as the current viewer.
    def viewer_is_followee?(viewer)
      viewer && viewer.id == target_id
    end

    def followable_user_id(viewer)
      viewer_is_followee?(viewer) ? actor_id : target_id
    end

    def followable_user_login(viewer)
      viewer_is_followee?(viewer) ? actor_login : target_login
    end

    def actor_bio_html
      return @actor_bio_html if defined?(@actor_bio_html)
      @actor_bio_html = if sender_record && sender_record.profile_bio.present?
        GitHub::Goomba::ProfileBioPipeline.to_html(sender_record.profile_bio, {})
      end
    end

    def target_bio_html
      @target_bio_html ||= GitHub::Goomba::ProfileBioPipeline.to_html(target_bio, {})
    end

    private

    def target_info_present?
      return true if target_followers_count && target_followers_count > 0
      return true if target_public_repos_count && target_public_repos_count > 0
      target_bio.present?
    end

    def target_text
      target_login || "(deleted)"
    end
  end
end
