# typed: strict
# frozen_string_literal: true

module Notifyd
  class CodeScanningAlertAdapter < SubjectAdapter
    include GitHub::Memoizer

    RelatedTopics = T.type_alias { T::Array[T::Hash[Symbol, String]] }
    Attributes = T.type_alias { T::Array[T::Hash[Symbol, String]] }
    FeatureSwitches = T.type_alias { T::Hash[Symbol, T::Boolean] }

    sig { returns(T::Boolean) }
    def matches?
      subject.repository.present? && subject.repository.owner.present?
    end

    sig { returns(Notifyd::SubjectAdapter::NotifyFeatureFlag) }
    def notify_feature_flag
      NotifyFeatureFlag.new(:notifyd_code_scanning_alert_events)
    end

    sig { returns(String) }
    def notification_id
      "#{subject.repository.permalink(include_host: false)}/security/code-scanning/#{subject.alert_number}"
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      subject.repository&.id
    end

    sig { returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_attributes
      subject.authzd_attributes
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def saml_enforcement
      owner = subject.repository.owner
      owner&.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Mobile::Basic)) }
    def mobile_layout
      nil
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Email::Basic)) }
    def email_layout
      Email::CodeScanningAlertRenderer.new(
        subject:,
        actor: context[:actor],
        operation:,
        assignee: context[:assignee],
        beacon_url: email_beacon_url(context[:actor], "code_scanning_alert", related_topics),
      ).render
    end

    sig { returns(RelatedTopics) }
    def related_topics
      [
        { type: "repository", value: subject.repository.id.to_s },
        { type: "code_scanning_alert", value: subject.alert_number.to_s },
      ]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def explicit_recipients
      case operation
      when Operations::CodeScanningAlertOperation::Assigned
        [{ reason: "assign", users: [context[:assignee]] }]
      when Operations::CodeScanningAlertOperation::Dismissed
        [{ reason: "state_change", users: context[:assignees] }]
      else
        []
      end
    end

    sig { returns(Attributes) }
    def attributes
      [
        { name: "thread_participant_activity", value: "true" },
        { name: "watch_activity", value: "true" },
        { name: "actor_id", value: context[:actor].id.to_s },
      ]
    end

    sig { returns(T.nilable(String)) }
    def trigger
      operation.serialize
    end

    sig { returns(T.nilable(Integer)) }
    def owner_id
      subject.repository.owner&.id
    end

    sig { returns(Symbol) }
    def owner_type
      subject.repository.owner.user? ? :user : :organization
    end

    sig { returns(FeatureSwitches) }
    def feature_switches
      { notify_subscribers: false }
    end

    private

    sig { returns(Operations::CodeScanningAlertOperation) }
    memoize def operation
      context[:operation]
    end
  end
end
