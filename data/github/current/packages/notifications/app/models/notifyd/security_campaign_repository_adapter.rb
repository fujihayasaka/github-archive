# typed: strict
# frozen_string_literal: true

module Notifyd
  class SecurityCampaignRepositoryAdapter < SubjectAdapter

    THREAD_TYPE = T.let("security_alert".freeze, String)

    include GitHub::Memoizer

    sig { returns(T::Boolean) }
    def matches?
      subject.valid? && repository.present? && repository.owner.present?
    end

    sig { returns(Flipper::Feature) }
    def notify_feature_flag
      GitHub.flipper[:notifyd_security_campaign_repository_subscriptions]
    end

    sig { returns(String) }
    def notification_id
      subject.permalink(include_host: false)
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      repository.id
    end

    sig { returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_attributes
      subject.authzd_attributes
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def saml_enforcement
      { organization_id: organization.id }
    end

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Mobile::Basic)) }
    def mobile_layout
      nil
    end

    sig { returns(Notifyd::Proto::Layouts::Email::Basic) }
    def email_layout
      Email::SecurityCampaignRepositoryRenderer.new(subject:, actor: T.must(actor), operation:, context:).render
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: "security_campaign_repository", value: subject.id.to_s },
        { type: "security_campaign", value: subject.security_campaign_id.to_s },
      ]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def explicit_recipients
      GitHub.dogstats.distribution_time("security_campaign_repository_adapter.explicit_recipients_load") do
        # Find all users that have read access to the repository. If someone doesn't have code scanning read permission
        # (e.g. they only have read access), it will be filtered out later when notifyd calls authzd. Unfortunately,
        # authzd doesn't support enumerating by a fine-grained permission, so this is the best we can do without manually
        # making a SQL query.
        authzd_request = Authzd::Enumerator::ForSubjectRequest.new(
          subject_id: repository_id,
          subject_type: "Repository",
          actor_type: "User",
          options: Authzd::Enumerator::Options.new(relationship: "read"),
        )
        response = T.let(Authzd.enumerator_client.for_subject(authzd_request), Twirp::ClientResp[Authzd::Enumerator::ForSubjectResponse])
        return [] if response.error.present?

        authorized_user_ids = response.data.result_ids.to_a
        GitHub.dogstats.count("security_campaign_repository_adapter.explicit_recipients_load.subscribed_size", authorized_user_ids.size, tags: ["trigger:#{trigger}", "kind:authorized"])
        return [] if authorized_user_ids.empty?

        # Find all users that are subscribed to security alerts for the repository
        user_ids_to_notify = T.let(SecurityAlert.user_ids_subscribed_to_security_alerts(repository, authorized_user_ids), T::Array[Integer])
        GitHub.dogstats.count("security_campaign_repository_adapter.explicit_recipients_load.subscribed_size", user_ids_to_notify.size, tags: ["trigger:#{trigger}", "kind:notify"])
        return [] if user_ids_to_notify.empty?

        users_to_notify = User.where(id: user_ids_to_notify).find_in_batches.to_a.flat_map(&:to_a)

        # Check if these users are subscribed to email notifications.
        users_to_notify = users_to_notify.select do |user|
          settings = GitHub.newsies.settings(user)
          settings.success? && settings.subscribed_email?
        end

        GitHub.dogstats.count("security_campaign_repository_adapter.explicit_recipients_load.subscribed_size", users_to_notify.size, tags: ["trigger:#{trigger}", "kind:email"])

        return [] if users_to_notify.empty?

        [{ reason: THREAD_TYPE, users: users_to_notify }]
      end
    end

    sig { returns(T.nilable(T::Array[T.untyped])) }
    def attributes
      nil
    end

    sig { returns(Integer) }
    def owner_id
      repository.owner_id
    end

    sig { returns(Symbol) }
    def owner_type
      repository.owner&.user? ? :user : :organization
    end

    sig { returns(T.nilable(String)) }
    def trigger
      context[:operation]
    end

    private

    sig { returns(Repository) }
    memoize def repository
      subject.repository
    end

    sig { returns(::Organization) }
    memoize def organization
      T.must(security_campaign.organization)
    end

    sig { returns(::SecurityCampaigns::SecurityCampaign) }
    memoize def security_campaign
      subject.security_campaign
    end

    sig { returns(T.nilable(::User)) }
    memoize def actor
      User.find_by(id: context[:actor_id])
    end

    sig { returns(Operations::SecurityCampaignRepositoryOperation) }
    memoize def operation
      Operations::SecurityCampaignRepositoryOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
