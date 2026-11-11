# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ExternalIdentitiesBusinessIds < Base
      iterate_over :database_table, params: {
        model_class: ExternalIdentity,
        conditions: "business_id IS NULL AND (provider_type = 'Business::SamlProvider' OR provider_type = 'Business::OIDCProvider')",
        columns: %i[provider_id provider_type],
      }

      # default number of items in this Batch will be 1000 for GHES and only 10 as default for dotcom with a upper limit of 100
      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if GitHub.single_business_environment?
          process_ghes(items)
          return
        end

        items_with_saml_provider = Hash.new { |hash, key| hash[key] = [] }
        items_with_oidc_provider = Hash.new { |hash, key| hash[key] = [] }
        items.each do |external_identity_id, row|
          case row[:provider_type]
          when "Business::SamlProvider"
            items_with_saml_provider[row[:provider_id]] << external_identity_id
          when "Business::OIDCProvider"
            items_with_oidc_provider[row[:provider_id]] << external_identity_id
          end
        end

        process_provider_group(
          ext_id_items: items_with_saml_provider,
          provider_model: Business::SamlProvider,
        )

        process_provider_group(
          ext_id_items: items_with_oidc_provider,
          provider_model: Business::OIDCProvider,
        )
      end

      sig do
        params(
          ext_id_items: T::Hash[Integer, T::Array[Integer]],
          provider_model: T.class_of(ApplicationRecord::Domain::Users),
        ).void
      end
      def process_provider_group(ext_id_items:, provider_model:)
        return if ext_id_items.empty?

        # fetching all the provider IDs and their corresponding business IDs in the batch to avoid N+1 queries when processing each item
        provider_ids = ext_id_items.keys

        business_id_by_provider_id = provider_model.where(id: provider_ids).pluck(:id, :business_id).to_h
        ids_by_business_id = Hash.new { |h, k| h[k] = [] }
        skipped_counts_by_provider_id = Hash.new(0)

        # going through each provider and group their external identities by business
        ext_id_items.each do |provider_id, external_identity_ids|
          business_id = business_id_by_provider_id[provider_id]

          if business_id.nil?
            # Enables logging if we can't find the business for a given provider
            # This can happen if there are external identities with provider_ids that don't have a corresponding provider record,
            # which would be unexpected but we want to be cautious in this transition.
            skipped_counts_by_provider_id[provider_id] += 1
            next
          end

          ids_by_business_id[business_id].concat(external_identity_ids)
        end

        skipped_counts_by_provider_id.each do |provider_id, count|
          log("Skipping #{count} ExternalIdentity rows for #{provider_model} id=#{provider_id}: could not determine business_id")
        end

        ids_by_business_id.each do |business_id, identity_ids|
          if dry_run?
            log("Would have updated #{identity_ids.size} ExternalIdentity rows for #{provider_model} with business_id #{business_id}")
          else
            log("Updating #{identity_ids.size} ExternalIdentity rows for #{provider_model} with business_id #{business_id}")
            write_to(model_class: ExternalIdentity) do
              ExternalIdentity.where(id: identity_ids).update_all(business_id: business_id)
            end
          end
        end
      end

      sig { params(items: Iterators::Items).void }
      def process_ghes(items)
        global_business_id = GitHub.global_business&.id
        if global_business_id.nil?
          log("No global business found for single business environment, cannot backfill business_id for ExternalIdentities")
          return
        end

        if dry_run?
          log("Would have updated #{items.size} ExternalIdentity rows with global business_id #{global_business_id}")
        else
          log("Updating #{items.size} ExternalIdentity rows with global business_id #{global_business_id}")
          write_to(model_class: ExternalIdentity) do
            ExternalIdentity.where(id: items.keys).update_all(business_id: global_business_id)
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

  GitHub::Transitions::ExternalIdentitiesBusinessIds.new(args).run
end
