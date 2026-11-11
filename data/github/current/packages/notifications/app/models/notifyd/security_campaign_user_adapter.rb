# typed: strict
# frozen_string_literal: true

module Notifyd
  class SecurityCampaignUserAdapter < SubjectAdapter
    THREAD_TYPE = T.let("security_alert".freeze, String)

    include GitHub::Memoizer

    sig { returns(T::Boolean) }
    def matches?
      subject.valid? && user.present?
    end

    sig { returns(Notifyd::SubjectAdapter::NotifyFeatureFlag) }
    def notify_feature_flag
      # TODO: add a feature flag for consolidated security campaign notifications
      NotifyFeatureFlag.new(:notifyd_security_campaign_user_subscriptions)
    end

    sig { returns(String) }
    def notification_id
      subject.permalink(include_host: false)
    end

    sig { returns(T.nilable(Integer)) }
    def repository_id
      nil
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

    sig { returns(T.nilable(Notifyd::Proto::Layouts::Email::Basic)) }
    def email_layout
      Email::SecurityCampaignUserRenderer.new(
        subject:,
        actor: T.must(actor),
        operation:,
        alert_counts_by_repo: alert_counts_by_repo,
        beacon_url: email_beacon_url(actor, "security_campaign_user", related_topics),
        repo_counts: repo_counts,
      ).render
    end

    sig { returns(T::Hash[Integer, Integer]) }
    def alert_counts_by_repo
      if context.key?(:alert_counts_by_repo)
        # Hashes can't have integer keys when used an an ActiveJob param
        context[:alert_counts_by_repo].transform_keys(&:to_i)
      elsif context.key?(:repo_counts_by_repo)
        JSON.parse(context[:repo_counts_by_repo]).transform_keys(&:to_i)
      else
        {}
      end
    end

    sig { returns(T.nilable(Turboscan::Proto::CountsByRepoResponse)) }
    def repo_counts
      return nil if context[:repo_counts_json].nil?

      parsed = JSON.parse(context[:repo_counts_json])
      repo_counts = (parsed["repository_counts"] || []).map do |rc|
        Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
          repository_id: rc["repository_id"],
          open_count: rc["open_count"],
          closed_count: rc["closed_count"],
        })
      end

      Turboscan::Proto::CountsByRepoResponse.new({
        open_count: parsed["open_count"],
        closed_count: parsed["closed_count"],
        repository_counts: repo_counts,
      })
    rescue StandardError => e
      # Fall back to nil so the renderer can refetch counts directly rather than
      # failing the entire notification delivery on a malformed payload.
      Failbot.report(e, context: "Failed to deserialize repo_counts_json for security campaign user #{subject.id}")
      nil
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def related_topics
      [
        { type: "organization", value: subject.security_campaign.organization_id.to_s },
        { type: "security_campaign", value: subject.security_campaign_id.to_s },
      ]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def explicit_recipients
      [{ reason: THREAD_TYPE, users: [user] }]
    end

    sig { returns(T.nilable(T::Array[T.untyped])) }
    def attributes
      nil
    end

    sig { returns(Integer) }
    def owner_id
      organization.id
    end

    sig { returns(Symbol) }
    def owner_type
      organization.user? ? :user : :organization
    end

    sig { returns(T.nilable(String)) }
    def trigger
      context[:operation]
    end

    private

    sig { returns(User) }
    memoize def user
      subject.user
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

    sig { returns(Operations::SecurityCampaignUserOperation) }
    memoize def operation
      Operations::SecurityCampaignUserOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
