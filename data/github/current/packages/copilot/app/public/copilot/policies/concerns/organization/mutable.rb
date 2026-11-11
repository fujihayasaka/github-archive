# typed: strict
# frozen_string_literal: true

# The Organization::Mutable module is responsible for enabling mutable operations on organization policies.

module Copilot
  module Policies
    module Concerns
      module Organization
        module Mutable
          extend T::Helpers
          include Kernel
          include Copilot::Policy

          requires_ancestor { Copilot::Policies::Concerns::Core }

          abstract!

          sig { abstract.params(copilot_organization: Copilot::Organization).returns(PolicyDescription) }
          def organization_setting_description(copilot_organization); end

          # whether or not the given org's policy is inherited from the business
          sig { params(org: Copilot::Organization).returns(T::Boolean) }
          def org_policy_inherited?(org)
            # get the business config
            business = org.business
            return false unless business

            ff_sources = [org.business, org].compact
            if ff_sources.any? { |source| source.feature_flag_enabled?(:use_setting_rules_copilot_models, default: false) } && setting_rules_supported_policy?
              result = CopilotDomain.domain.settings.get_inherited_value(org, Copilot::Settings::CopilotModelSetting,
                setting_name: "copilot.models.supported_models.#{config_name}")
              if org.feature_flag_enabled?(:copilot_unconfigured_is_inherited, default: false)
                result != Copilot::Settings::CopilotModelSetting::Value::NO_POLICY
              else
                [Copilot::Settings::CopilotModelSetting::Value::NO_POLICY, Copilot::Settings::CopilotModelSetting::Value::UNCONFIGURED].exclude?(result)
              end
            else
              copilot_biz = Copilot::Business.new(business)
              if copilot_biz.feature_flag_enabled?(:copilot_unconfigured_is_inherited, default: false)
                # if the business is unconfigured and the org enabled their policy, we should allow them to set it to disabled
                if copilot_biz.feature_flag_enabled?(:copilot_unconfigured_editable_when_enabled, default: false) && unconfigured?(copilot_biz) && enabled?(org)
                  GitHub.logger.info("Unconfigured business and org enabled policy - org can edit", {
                    "gh.organization.id" => org.id,
                    "gh.business.id" => copilot_biz.id,
                    "gh.copilot.policy.name" => config_name,
                  })
                  GitHub.dogstats.increment(
                    "copilot.settings.org_inherited_check.biz_unconfigured_org_enabled",
                    tags: ["policy:#{config_name}"],
                  )
                  return false
                end

                return false if no_policy?(copilot_biz)
              else
                return false if no_policy?(copilot_biz) || unconfigured?(copilot_biz)
              end

              true
            end
          end

          sig { overridable.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
          def editable_by_org?(copilot_org)
            return false unless viewable_by_org?(copilot_org)

            # orgs cannot edit their policy if it is inherited from the business
            return false if org_policy_inherited?(copilot_org)

            true
          end

          # whether or not to show this policy to the given organization
          sig { overridable.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
          def viewable_by_org?(copilot_org)
            # by default, if the policy is available, show it.
            available_for?(copilot_org)
          end

          sig { overridable.params(copilot_org: Copilot::Organization, value: String, force: T::Boolean, send_email: T::Boolean).void }
          def update_org(copilot_org, value, force: false, send_email: true)
            # don't allow updates if the policy is not available for the org
            return unless available_for?(copilot_org)

            # we normally should not let the org update their policy if the orgs business has a policy set
            # however, we allow overriding this behavior in order to enable policy propagation from business to org
            return if org_policy_inherited?(copilot_org) && !force

            # don't allow setting to unconfigured in the paved path
            return if value == config_values[:unconfigured]

            previous_value = value(copilot_org)

            update!(copilot_org.configuration, value)

            # update datadog counters
            GitHub.dogstats.increment(
              "copilot.settings.#{config_name}_#{value}",
              tags: ["type:organization"],
            )
            GitHub.dogstats.increment(
              "copilot.settings.updated",
              tags: ["type:organization", "policy_name:#{config_name}", "policy_value:#{value}"]
            )

            post_organization_update(copilot_org, value)

            if self.is_a?(Copilot::Policies::Concerns::Organization::Mailable) && send_email
              T.bind(self, Copilot::Policies::Concerns::Organization::Mailable)
              send_policy_updated_email(copilot_org, value: value, previous_value: previous_value)
            end

            Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_org.id)
          end

          # noop to be optionally overridden
          sig { overridable.params(copilot_org: Copilot::Organization, value: String).void }
          def post_organization_update(copilot_org, value); end
        end
      end
    end
  end
end
