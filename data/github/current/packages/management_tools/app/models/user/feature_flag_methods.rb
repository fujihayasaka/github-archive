# typed: true
# frozen_string_literal: true

# See https://thehub.github.com/engineering/products-and-services/dotcom/features/feature-flags/overview/
class User
  module FeatureFlagMethods
    extend T::Helpers

    include GitHub::ResilienceMixin
    include GitHub::FlipperActor
    include GitHub::VexiActor
    include User::PreReleaseFeaturesMethods
    include Configurable::ProgrammaticAccessTokensOptIn
    include User::EnterpriseManagedDependency
    include GitHub::Memoizer
    # include ApplicationController::RolesDependency

    # Public: Determine if features like device verification challenges and
    # unrecognized sign in location alerts. The goal is to entirely bypass
    # writes while reducing reads of AuthenticationRecords and
    # AuthenticatedDevices.
    def sign_in_analysis_enabled?
      GitHub.sign_in_analysis_enabled? &&
        !GitHub.flipper[:verified_device_enforcement_opt_out].enabled?(self)
    end

    # Public: Enable the given feature preview for this user.
    #
    # feature - String or Symbol feature flag name
    #
    # Returns a Boolean: true if the user was added to the feature, false if the feature
    # is not an eligible feature preview.
    def enable_feature_preview(feature)
      result = enable_edge_feature(feature)
      reset_feature_preview_memoization(feature)
      result
    end

    # Public: Disable the given feature preview for this user.
    #
    # feature - String or Symbol feature flag name
    #
    # Returns nothing.
    def disable_feature_preview(feature)
      result = disable_edge_feature(feature)
      reset_feature_preview_memoization(feature)
      result
    end

    # Public: Check if this user has opted into a feature preview.
    #
    # feature_name - String or Symbol feature flag name
    # enrolled_by_default_override - Boolean or nil, if present, overrides the default enrollment check
    #
    # Returns a Boolean: true if the feature is a feature preview and the user is in it.
    def feature_preview_enabled?(feature_name, enrolled_by_default_override: nil)
      before = Time.now
      feature_name = feature_name.to_s
      stats_tags = ["feature:#{feature_name}"]

      if !checked_feature_previews.key?(feature_name)
        value = with_database_error_fallback(fallback: false) do
          feature = ActiveRecord::Base.connected_to(role: :reading) do
            Feature.find_by(slug: feature_name)
          end

          stats_tags << if feature.present?
            "feature_found:true"
          else
            "feature_found:false"
          end

          enrolled_in_feature_preview?(feature, enrolled_by_default_override)
        end

        GitHub.dogstats.increment("beta_feature.enabled_check", tags: stats_tags)
        @checked_feature_previews[feature_name] = {
          enabled: value,
          duration: 0,
          times_checked: 0,
        }
      end

      feature_preview_enabled = checked_feature_previews.dig(feature_name, :enabled)
      @checked_feature_previews[feature_name][:times_checked] += 1
      duration = Time.now - before
      @checked_feature_previews[feature_name][:duration] += duration
      GitHub.dogstats.timing("beta_feature.enabled_check.duration", duration * 1000, tags: stats_tags)
      feature_preview_enabled
    end

    def checked_feature_previews
      @checked_feature_previews ||= {}
    end

    private def enrolled_in_feature_preview?(feature, enrolled_by_default_override)
      return false unless feature&.viewer_can_read?(self)

      enrollment = ActiveRecord::Base.connected_to(role: :reading) do
        feature.enrollments.find_by(enrollee: self)
      end

      if enrollment
        # User has set an explicit preference
        enrollment.enrolled?
      else
        # If enrolled_by_default_override is present, use the override.
        # Otherwise, we know nothing about this user's preference so we
        # use the default.
        !enrolled_by_default_override.nil? ? enrolled_by_default_override : feature.enrolled_by_default?
      end
    end

    private def reset_feature_preview_memoization(key = nil)
      return unless defined?(@checked_feature_previews)

      if key
        @checked_feature_previews.delete(key.to_s)
      else
        remove_instance_variable(:@checked_feature_previews)
      end
    end

    # Does this user have access to staff-only features on github.com? Make sure
    # to use this method instead of `User#site_admin?` for early access github.com
    # features, otherwise these features will be visible to Enterprise admins.
    #
    # Returns a Boolean.
    def preview_features?
      T.bind(self, User)
      return unless GitHub.preview_features_enabled?

      # Disable preview_features when employee mode is disabled for a user
      return false if respond_to?(:disabled_employee_mode?) && disabled_employee_mode?

      if GitHub.enterprise?
        enterprise_preview_features?
      else
        employee? && !preview_features_opt_out?
      end
    end

    memoize def preview_features_opt_out?
      !GitHub.enterprise? && preview_features_opt_out_team?
    end

    # Does this user have access to preview features on Enterprise? This method
    # should be used for early access to Enterprise features that should not
    # be visible to Enterprise admins (customers) just yet.
    #
    # Returns a Boolean.
    memoize def enterprise_preview_features?
      GitHub.enterprise? && enterprise_preview_features_team?
    end

    # Does this user have access to some open-source maintainers-relevant
    # early access features on GitHub.com?
    #
    # Returns a Boolean.
    def maintainers_early_access?
      !GitHub.enterprise? && maintainers_early_access_team?
    end

    # Does this user have access to integrators early access features?
    #
    # Returns a Boolean.
    def integrators_early_access?
      !GitHub.enterprise? && integrators_early_access_team?
    end

    # Is this user a Microsoft MVP?
    #  - MVPs have a coupon in the format MVP-xxxxxxx
    #  See https://github.com/github/copilot-planning/issues/1462
    #
    # Returns a Boolean.
    def microsoft_mvp?
      T.bind(self, User)
      return false if GitHub.enterprise?
      return false unless coupon_redemption.present?

      coupon = coupon_redemption&.coupon

      return false unless coupon.present?
      return false unless coupon.respond_to?(:code)
      coupon.code.start_with?("MVP-")
    end

    # Should this user see prerelease badges for features they have early access to
    # Currently only visible to the open source maintainers EAP and staff
    #
    # Returns boolean
    def prerelease_badges?
      !GitHub.enterprise? && (maintainers_early_access? || preview_features?)
    end

    def abilities_team_enabled?
      preview_features? && abilities_team?
    end

    # New security feature to require callback url registration and validation.
    def oauth_registered_callback_urls_enabled?
      GitHub.flipper[:oauth_multiple_callback_urls].enabled?(self)
    end

    # Internal: Is this an abilibuddy?
    def abilities_team?
      team_access? :abilities
    end

    # Internal: Is this user a stafftooler
    def stafftools_team?
      team_access? :stafftools
    end

    def user_security_team?
      team_access? :user_security
    end

    # Does this user have "operator mode" as it pertains to git pushes?  When
    # set, additional log info is echoed back to users' terminals including
    # timings of custom pre-receive hook messages.  Enabled only for GHE
    # because this runs for every git operation, and `site_admin?` uses
    # expensive queries.
    def has_operator_mode?(conf)
      T.bind(self, User)
      GitHub.enterprise? && site_admin? && ![nil, "false"].include?(conf["operator_mode"])
    end

    def preview_features_opt_out_team?
      team_access? :staffship_optout
    end

    def enterprise_preview_features_team?
      team_access? :enterprise_preview_features
    end

    def maintainers_early_access_team?
      team_access? :maintainers_early_access
    end

    def integrators_early_access_team?
      team_access? :integrators_early_access
    end

    # Does this user have permissions to access the SIRE GraphQL mutations?
    # - If we're in Dotcom, the user needs to be a member of github/sire-hubbers
    # - If we're in Proxima, we need to verify that
    #   this user is present in the IdP group *in the Stafftools tenant*;
    def security_incident_response_access?
      T.bind(self, User)
      # `github/sire-hubbers` is only present in Dotcom
      unless GitHub.multi_tenant_enterprise?
        return team_access?(:sire) && self.site_admin?
      end

      # We need to ensure we are only checking the stafftools tenant
      # because one could create an IdP group in their own tenant;
      # additionally, the stafftools tenant should nominally be the only
      # tenant with cross-tenant access
      return false unless GitHub::CurrentTenant.stafftools_tenant?

      external_provider = GitHub::CurrentTenant.get&.external_provider
      return false unless external_provider

      group = ExternalGroup.by_provider(external_provider).where(display_name: ["sire-hubbers"]).first
      return false unless group

      group.active_user?(self)
    end

    # Adding user group for GitHub-stacks collaboration
    def azure_stacks_collaborators?
      !GitHub.enterprise? && azure_stacks_collaborators_team?
    end

    def azure_stacks_collaborators_team?
      team_access? :azure_stacks_collaborators
    end

    def stacks_contributors?
      !GitHub.enterprise? && stacks_contributors_team?
    end

    def stacks_contributors_team?
      team_access? :stacks_contributors
    end

    def microsoft_everyone_team_access?
      return @microsoft_everyone_team_access if defined?(@microsoft_everyone_team_access)
      @microsoft_everyone_team_access = team_access?(:microsoft)
    end

    # Is codesearch disabled for the current user? This feature flag is used to
    # block users that are negatively impacting the Elasticsearch cluster.
    #
    # see https://devportal.githubapp.com/feature-flags/disable_codesearch/overview
    #
    # Returns a Boolean.
    def codesearch_disabled?
      GitHub.flipper[:disable_codesearch].enabled?(self)
    end

    # Internal: Checks if the user is a member of a team.
    #
    # team - Symbol name for a Team that matches a FeatureFlagMethods class
    #        method that loads a team.  `:early_access` will check against
    #        FeatureFlagMethods.early_access_team.
    #
    # Returns a Boolean.
    def team_access?(team)
      GitHub::FeatureFlag.user_team_access?(team, self)
    end

    def org_access?(org)
      GitHub::FeatureFlag.user_org_access?(org, self)
    end

    def shopify_org?
      return @in_shopify_org if defined?(@in_shopify_org)
      @in_shopify_org = !GitHub.enterprise? && org_access?(:shopify)
    end

    # Internal: Does the user have access to a feature based on a pattern contained in their email address?
    # See app/models/user/email_suffix_actor.rb for more details on this method of enabling features.
    #
    # Returns a Boolean.
    def feature_enabled_via_email_suffix?(feature_name)
      GitHub.flipper[feature_name].enabled?(User::EmailSuffixActor.from_user(self))
    end

    # Public: Check if slash commands are enabled for user.
    #
    # Returns Boolean
    def slash_commands_enabled?
      return @slash_commands_enabled if defined?(@slash_commands_enabled)
      # use `slash_commands` for direct enrollment into the feature
      # the `slash_commands_beta` enables Feature Preview (opt-in) for select closed beta participants
      @slash_commands_enabled = GitHub.flipper[:slash_commands].enabled?(self) || feature_preview_enabled?(:slash_commands_beta)
    end

    # Public: Check if custom slash commands are enabled for user.
    #
    # Returns Boolean
    def custom_slash_commands_enabled?
      return @custom_slash_commands_enabled if defined?(@custom_slash_commands_enabled)

      # Custom slash commands are restricted to users who have slash commands enabled and are also
      # part of an additional flag.
      @custom_slash_commands_enabled = slash_commands_enabled? && feature_enabled?(:user_defined_commands)
    end

    def show_spammy_issues_to_staff_enabled?
      T.bind(self, User)
      return @show_spammy_issues_to_staff_enabled if defined?(@show_spammy_issues_to_staff_enabled)
      @show_spammy_issues_to_staff_enabled = self.site_admin? && GitHub.flipper[:show_spammy_issues_to_staff].enabled?(self)
    end

    def reviewable_state_searching_enabled?
      return @reviewable_state_searching_enabled if defined?(@reviewable_state_searching_enabled)
      @reviewable_state_searching_enabled = GitHub.flipper[:reviewable_state_searching].enabled?(self)
    end

    # Public: Check if the User or Organization has the new Personal Access
    # Tokens feature turned on. If a Business has enabled the feature all
    # organizations in that business will also be enabled.
    #
    # Returns a Boolean.
    def patsv2_enabled?
      true
    end

    # Overwrite the flipper_actor_name in GitHub::FlipperActor
    sig { override.returns(String) }
    def flipper_actor_name
      T.bind(self, User)
      display_login
    end

    # Overwrite the flipper_actor_display_name in GitHub::FlipperActor
    sig { override.returns(T.nilable(String)) }
    def flipper_actor_display_name
      T.bind(self, User)
      profile_name
    end

    # Provide a custom implementation of the from_flipper_actor_name class method to override the one in GitHub::FlipperActor
    module ClassMethods
      sig { params(name: String).returns(T.nilable(GitHub::FlipperActor)) }
      def from_flipper_actor_name(name)
        User.find_by_login name
      end
    end

    mixes_in_class_methods(ClassMethods)

    # Overwrite the actor_tenant in GitHub::FlipperActor
    def actor_tenant
      if GitHub.multi_tenant_enterprise? && enterprise_managed_business
        tenant = enterprise_managed_business
        FeatureManagement::ActorTenant.new(T.unsafe(tenant).name, T.unsafe(tenant).id)
      else
        nil
      end
    end
  end
end
