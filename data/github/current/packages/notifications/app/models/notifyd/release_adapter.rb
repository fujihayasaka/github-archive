# typed: true
# frozen_string_literal: true

module Notifyd
  class ReleaseAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    THREAD_TYPE = "release".freeze

    def matches?
      # When Notifyd::NotifyPublisher is called asynchronously, some of the dependencies may have been removed
      # For example, the associated repository may no longer exist
      # We prevent errors by making these checks:
      repository.present? && repository.owner.present?
    end

    def notify_feature_flag
      NotifyFeatureFlag.new(:notifyd_release_notify)
    end

    def notification_id
      subject.permalink(include_host: false)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      subject.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      Mobile::ReleaseRenderer
        .new(release: subject, author: Mobile::AuthorUser.new(user: actor))
        .render
    end

    def email_layout
      nil
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: THREAD_TYPE, value: subject.id.to_s },
      ]
    end

    def attributes
      [
        { name: "thread_type", value: THREAD_TYPE },
        { name: "watch_activity", value: "true" },
        { name: "actor_id", value: actor&.id.to_s },
      ]
    end

    def explicit_recipients
      # TODO: Handle explicitly at-mentioned users in the body of the release notes.
      []
    end

    def owner_id
      repository.owner.id
    end

    def owner_type
      repository.owner.user? ? :user : :organization
    end

    def trigger
      context[:operation]
    end

    private

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def repository
      @repository ||= subject.repository
    end
  end
end
