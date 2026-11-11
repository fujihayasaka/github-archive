# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillExternalGroupsBusinessId < Base

      iterate_over :database_table, params: {
        model_class: ExternalGroup,
        conditions: "business_id IS NULL",
        columns: %i[id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        external_group_ids = items.keys

        if GitHub.single_business_environment?
          if dry_run?
            log("Would have updated #{external_group_ids.size} external groups (sample: #{external_group_ids.first(10)}) with business_id #{GitHub.global_business.id}")
          else
            log("Updating #{external_group_ids.size} external groups (sample: #{external_group_ids.first(10)}) with business_id #{GitHub.global_business.id}")
            write_to(model_class: ExternalGroup) do
              ExternalGroup.where(id: external_group_ids).update_all(business_id: GitHub.global_business.id)
            end
          end
        else
          saml_provider_groups = ExternalGroup.where(id: external_group_ids, provider_type: "Business::SamlProvider")
          oidc_provider_groups = ExternalGroup.where(id: external_group_ids, provider_type: "Business::OIDCProvider")

          saml_ids = saml_provider_groups.pluck(:id)
          oidc_ids = oidc_provider_groups.pluck(:id)

          if dry_run?
            log("Would have updated #{saml_ids.size} SAML external groups (sample: #{saml_ids.first(10)})")
            log("Would have updated #{oidc_ids.size} OIDC external groups (sample: #{oidc_ids.first(10)})")
          else
            log("Updating #{saml_ids.size} SAML external groups (sample: #{saml_ids.first(10)})")
            log("Updating #{oidc_ids.size} OIDC external groups (sample: #{oidc_ids.first(10)})")

            write_to(model_class: ExternalGroup) do
              saml_provider_groups
                .joins("INNER JOIN business_saml_providers ON business_saml_providers.id = external_groups.provider_id")
                .update_all("external_groups.business_id = business_saml_providers.business_id")
            end

            write_to(model_class: ExternalGroup) do
              oidc_provider_groups
                .joins("INNER JOIN business_oidc_providers ON business_oidc_providers.id = external_groups.provider_id")
                .update_all("external_groups.business_id = business_oidc_providers.business_id")
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillExternalGroupsBusinessId.new(args).run
end
