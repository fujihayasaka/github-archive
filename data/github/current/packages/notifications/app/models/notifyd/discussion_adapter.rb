# typed: true
# frozen_string_literal: true

module Notifyd
  class DiscussionAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    THREAD_TYPE = "discussion".freeze

    def matches?
      # When Notifyd::NotifyPublisher is called asynchronously, some of the dependencies may have been removed
      # For example, the associated repository may no longer exist
      # We prevent errors by making these checks:
      repository.present? && repository.owner.present?
    end

    def notify_feature_flag
      FeatureEnabled.new
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
      Mobile::DiscussionRenderer
        .new(discussion: subject, author: Mobile::AuthorUser.new(user: actor))
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
      nil
    end

    def explicit_recipients
      return [] unless context[:current_body]
      mention_diff = GitHub::MentionDiff.new(
        context[:previous_body] || "",  # Empty for create operation
        context[:current_body],
        subject.async_body_context.sync
      )
      recipients_with_reason(mention_diff.added_users)
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

    def recipients_with_reason(recipients)
      recipients.map do |mentioned_user|
        { reason: "mention", users: [mentioned_user] }
      end
    end
  end
end
