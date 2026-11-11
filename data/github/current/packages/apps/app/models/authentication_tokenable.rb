# typed: true
# frozen_string_literal: true

module AuthenticationTokenable
  extend T::Helpers
  extend ActiveSupport::Concern

  # Public: Generates a new authentication token for this record and
  # returns a result containing the token's plaintext value for use in making
  # API requests.
  #
  # code_path  - An optional String that represents where the token creation is
  #              being called from. Used for stats and availability.
  # redis_with_mysql_fallback - The Boolean determining if the caller wants to dual write the
  #              token to Redis and MySQL or just Redis with a MySQL fallback.
  #
  # Returns a GH::Result wrapping a CreateResult (which includes the plaintext
  # token and related metadata).
  def generate_token(code_path: nil, redis_with_mysql_fallback: false, s2s_stateless_override: nil)
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    integration_id = use_s2s_stateless_token?(s2s_stateless_override: s2s_stateless_override) ? self.integration&.id : nil

    result = if integration_id
      # Stateless tokens are issued by authnd — no local persistence needed regardless of redis setting
      ServerToServerTokens.domain.create(self.id, T.must(self.class.name), create_span_attributes, integration_id: integration_id, code_path: code_path)
    elsif redis_with_mysql_fallback
      ServerToServerTokens.domain.create_redis_with_mysql_fallback(self.id, T.must(self.class.name), create_span_attributes, code_path: code_path)
    else
      ServerToServerTokens.domain.create(self.id, T.must(self.class.name), create_span_attributes, integration_id: nil, code_path: code_path)
    end

    track_latest_writes(result)

    result
  end

  private def track_latest_writes(result)
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))

    return unless FeatureFlag.vexi.enabled?(:s2s_tokens_read_after_write_tracking, default: false) ||
      (self.integration && FeatureFlag.vexi.enabled?(:s2s_tokens_read_after_write_tracking, self.integration, default: false))

    return unless result.is_a?(GH::Result::Ok) && result.value.token_value.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      DatabaseSelector::LastOperations.from_token(result.value.token_value).store_latest_writes
    end
  end

  # Maps integration IDs to human-readable names for feature flag naming.
  # Flag names become e.g. :server_to_server_authnd_stateless_tokens_actions_github
  # If an integration ID isn't in this map, falls back to the numeric ID.
  # To add a new app, add its integration ID and desired flag name here.
  S2S_STATELESS_APP_FLAG_NAMES = T.let({
    15368 => "actions",
    15470 => "actions_lab",
    29110 => "dependabot",
    946600 => "copilot_pull_request_reviewer",
    1143301 => "copilot_swe_agent",
    54007 => "codespaces",
  }.freeze, T::Hash[Integer, String])

  # Returns the human-readable flag suffix for an integration, e.g. "actions" instead of "15368".
  # Falls back to the integration ID if not in the map.
  private def s2s_stateless_flag_suffix(integration)
    S2S_STATELESS_APP_FLAG_NAMES[integration.id] || integration.id.to_s
  end

  # Whether to issue a stateless S2S token via authnd.
  #
  # Rollout is gated per-integration with progressively wider scopes:
  #   1. Master gate on the integration (required for all paths)
  #   2. GitHub org target via github_org_targeted (falls through if disabled)
  #   3. GitHub-owned apps via github_org_owned (falls through if disabled)
  #   4. Per-app target rollout (falls through if disabled)
  #   5. Percentage rollout for the remaining third-party apps via 3p_apps
  #
  # Opt-outs force a stateful token and take precedence over the rollout scopes
  # above (but not over the :enabled header):
  #   - Header opt-in/opt-out via API (:enabled/:disabled)
  #   - Owner opt-out (owner_opt_out): opts out every app an org/business owns
  #   - Per-integration opt-out (integration_opt_out): kill switch for one app
  private def use_s2s_stateless_token?(s2s_stateless_override: nil)
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    integration = self.integration
    return false unless integration
    return false unless FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens, integration, default: false)

    # For better test coverage, bypass capability + target checks for tests unless explicitly disabled
    # so that any installation with the integration flag enabled issues stateless JWTs.
    # The opt-in/opt-out logic is also bypassed — test those paths explicitly.
    return true if GitHub.development_or_test_all_features?

    # Header opt-in (:enabled) trumps everything including org opt-out.
    # Header opt-out (:disabled) forces a stateful token regardless of flags.
    # The integration must still have the master flag enabled above.
    return true if s2s_stateless_override == :enabled
    return false if s2s_stateless_override == :disabled

    # Owner opt-out for all apps a company owns: allows an org/business that owns one or
    # more apps to opt every app they own out of stateless tokens. Applies regardless of
    # which integration is being used, as long as it shares the same owner. Honors the
    # :enabled header above. Checked against the integration's owner and the owner's
    # business (enterprise).
    owner = integration.owner
    if owner
      owner_opt_out_actors = [owner]
      owner_opt_out_actors << owner.business if owner.respond_to?(:business) && owner.business
      owner_opt_out_actors.compact!
      if FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens_owner_opt_out, *owner_opt_out_actors, default: false)
        return false
      end
    end

    # Per-integration opt-out: a kill switch that lets any single integration be temporarily
    # opted out of stateless tokens (e.g. to give an integration time to investigate an issue
    # if something occurs). Checked against the integration itself. Honors the :enabled header
    # above.
    if FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens_integration_opt_out, integration, default: false)
      return false
    end

    # GitHub org: single flag for integration-specific rollout targeting the GitHub org.
    # Falls through to the github_org_owned check below so GitHub-owned apps installed on
    # the GitHub org can be rolled out via that flag.
    if self.respond_to?(:target_id) && self.target_id == GitHub.first_party_apps_owner_id
      return true if FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens_github_org_targeted, integration, default: false)
    end

    # GitHub-owned apps: single flag checked against integration, falls through to per-integration target flag if false
    # Once we've rolled out the global integrations, this will let us enable other first-party apps that are owned by GitHub
    if integration.owner_id == GitHub.first_party_apps_owner_id
      return true if FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens_github_org_owned, integration, default: false)
    end

    suffix = s2s_stateless_flag_suffix(integration)

    # Per-app target rollout: per-integration flag checked against the target.
    # Return true if enabled
    target_flag = :"server_to_server_authnd_stateless_tokens_#{suffix}"
    if self.respond_to?(:target)
      return true if FeatureFlag.vexi.enabled?(target_flag, self.target, default: false)
    end

    # Remaining third-party apps: percentage-based rollout checked against the integration, so
    # apps without a dedicated per-app flag can be ramped up gradually by percentage.
    FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens_3p_apps, integration, default: false)
  rescue StandardError
    false
  end

  # Obtain all of the available attributes for `authenticatable` that we can send to Datadog (for create requests)
  #
  # Returns a Hash.
  def create_span_attributes
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))

    span_attributes = {
      "gh.authentication_token.authenticatable.id" => self.id,
      "gh.authentication_token.authenticatable.type" => self.class.name,
    }

    if self.respond_to?(:target_id) && self.respond_to?(:target_type)
      span_attributes["gh.installation.target.id"] = self.target_id
      span_attributes["gh.installation.target.type"] = self.target_type
    end

    if self.respond_to?(:parent)
      span_attributes["gh.parent_installation.id"] = T.cast(self, ScopedIntegrationInstallation).parent&.id
    end

    if self.respond_to?(:integration)
      integration = self.integration
      span_attributes["gh.integration.id"] = integration&.id
    end

    span_attributes
  end

  def valid_for_current_tenant?
    return true unless GitHub.multi_tenant_enterprise?

    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    GitHub::CurrentTenant.get == self.resolve_tenant
  end
end
