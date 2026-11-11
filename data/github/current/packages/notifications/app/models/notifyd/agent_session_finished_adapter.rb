# typed: strict
# frozen_string_literal: true

module Notifyd
  class AgentSessionFinishedAdapter < SubjectAdapter
    include GitHub::Memoizer
    include UrlHelpers

    sig { returns(T::Boolean) }
    def matches?
      subject.valid? && repository.present? && repository.owner.present?
    end

    sig { returns(SubjectAdapter::NotifyFeatureFlag) }
    def notify_feature_flag
      NotifyFeatureFlag.new
    end

    sig { returns(String) }
    def notification_id
      subject.notification_id
    end

    sig { returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_attributes
      repository.permissions_wrapper.serialized_subject_attributes
    end

    sig { returns(User) }
    def actor
      subject.user
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def saml_enforcement
      owner = T.must(repository.owner)
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Email::Basic)) }
    def email_layout
      Email::AgentSessionFinishedRenderer.new(
        notification: subject,
        actor: actor,
      ).render
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Mobile::Basic)) }
    def mobile_layout
      nil
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
      ]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def explicit_recipients
      [{ reason: "agent_session_finished", users: [actor] }]
    end

    sig { returns(T.nilable(T::Array[T.untyped])) }
    def attributes
      [
        { name: "session_state", value: subject.session_state },
      ]
    end

    sig { returns(Integer) }
    def owner_id
      T.must(repository.owner).id
    end

    sig { returns(Symbol) }
    def owner_type
      T.must(repository.owner).user? ? :user : :organization
    end

    sig { returns(T.nilable(String)) }
    def trigger
      context[:operation]
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      repository.id
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def feature_switches
      {
        notify_actor: true,
        notify_subscribers: false
      }
    end

    private

    sig { returns(::Repository) }
    memoize def repository
      T.cast(subject.repository, ::Repository)
    end
  end
end
