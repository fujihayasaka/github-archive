# typed: strict
# frozen_string_literal: true

module Notifyd
  class MemberFeatureRequestAdapter < SubjectAdapter

    Layouts = Notifyd::Proto::Layouts::Email
    include Notifyd::Email
    include UrlHelpers
    include GitHub::Memoizer

    sig { returns(T::Boolean) }
    def matches?
      subject.valid?
    end

    sig { returns(Flipper::Feature) }
    def notify_feature_flag
      GitHub.flipper[:raf_email_notifications_notifyd]
    end

    sig { returns(String) }
    def notification_id
      subject.notification_id
    end

    sig { returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_attributes
      subject.authzd_attributes
    end

    sig { returns(User) }
    def actor
      subject.user
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def saml_enforcement
      return { skip_enforcement: true } if entity.is_a?(Business)

      { organization_id: entity.id }
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Mobile::Basic)) }
    def mobile_layout
      nil
    end

    sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
    def email_layout
      Email::MemberFeatureRequestRenderer.new(subject, context).render
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def related_topics
      [
        { type: entity_type, value: entity.id.to_s },
      ]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def explicit_recipients
      [{ reason: "member_feature_requested", users: [actor] }]
    end

    sig { returns(T.nilable(T::Array[T.untyped])) }
    def attributes
      nil
    end

    sig { returns(Integer) }
    def owner_id
      actor.id
    end

    sig { returns(Symbol) }
    def owner_type
      :user
    end

    sig { returns(T.nilable(String)) }
    def trigger
      context[:operation]
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      nil
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def feature_switches
      {
        notify_actor: true,
        notify_subscribers: false
      }
    end

    private

    sig { returns(T.any(::User, ::Business)) }
    memoize def entity
      subject.entity
    end

    sig { returns(String) }
    def entity_type
      entity.is_a?(User) ? "organization" : "business"
    end
  end
end
