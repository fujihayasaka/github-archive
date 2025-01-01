# typed: strict
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
  class SponsorView < View
    sig { returns String }
    def title_text
      parts = [actor_text, "started sponsoring", target_text]
      parts.join(" ")
    end

    sig { returns T.nilable(Integer) }
    def actor_followers_count
      return @actor_followers_count if defined?(@actor_followers_count)
      @actor_followers_count = T.let(sender_record&.followers_count(viewer: nil), T.nilable(Integer))
    end

    sig { returns T.nilable(Integer) }
    def actor_public_repos_count
      return @actor_public_repos_count if defined?(@actor_public_repos_count)
      @actor_public_repos_count = T.let(
        sender_record ? sender_record.repository_counts.public_repositories : nil,
        T.nilable(Integer)
      )
    end

    sig { returns T.nilable(String) }
    def actor_avatar_url
      if sender_record
        sender_record.primary_avatar_url(80)
      end
    end

    sig { params(viewer: User).returns(T::Boolean) }
    def show_event_details?(viewer:)
      # Always show user details in the view when the current user is the one who was sponsored,
      # since we'll show info about the actor instead of the target.
      viewer_is_sponsorable?(viewer) || target_info_present?
    end

    # Public: Check if the user who was sponsored in this event is the same as the current viewer.
    sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
    def viewer_is_sponsorable?(viewer)
      !!(viewer && viewer.id == target_id)
    end

    sig { returns T.nilable(Integer) }
    def sponsor_button_target_user_id
      target_id
    end

    sig { returns T.nilable(String) }
    def sponsor_button_target_user_login
      target_login
    end

    sig { returns T.nilable(String) }
    def actor_bio_html
      return @actor_bio_html if defined?(@actor_bio_html)
      @actor_bio_html = T.let(nil, T.nilable(String))
      @actor_bio_html = if sender_record && sender_record.profile_bio.present?
        GitHub::Goomba::ProfileBioPipeline.to_html(sender_record.profile_bio, {})
      end
    end

    sig { returns T.nilable(String) }
    def target_bio_html
      @target_bio_html ||= T.let(GitHub::Goomba::ProfileBioPipeline.to_html(target_bio, {}), T.nilable(String))
    end

    private

    delegate :sender_record, :target_id, :target_login, :target_bio, :target_followers_count, \
      :target_public_repos_count, to: :event

    sig { returns Stratocaster::Event }
    def event
      T.cast(model, Stratocaster::Event)
    end

    sig { returns T::Boolean }
    def target_info_present?
      return true if target_followers_count && target_followers_count > 0
      return true if target_public_repos_count && target_public_repos_count > 0
      target_bio.present?
    end

    sig { returns String }
    def target_text
      target_login || "(deleted)"
    end
  end
end
