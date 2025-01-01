# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module MarketplaceSearchHelper
      include Kernel

      def async_formulate_query?(variables)
        category_slug = variables[:categorySlug]
        model_task = variables[:modelTask]
        publisher = variables[:publisher]
        verification_state = variables[:verificationState]
        query = variables[:searchQuery]
        type = variables[:searchType]

        if type == "models"
          if category_slug.present?
            query += %Q( category:"#{category_slug}")
          end

          if model_task.present?
            query += %Q( task:"#{model_task.downcase}")
          end

          if publisher.present?
            query += %Q( publisher:"#{publisher.downcase}")
          end
        end

        promise = if category_slug.present?
          Platform::Loaders::ActiveRecord.load(::Marketplace::Category, category_slug, column: :slug).then do |mkt_category|
            Platform::Loaders::ActiveRecord.load(::IntegrationFeature, category_slug, column: :slug).then do |wwg_category|
              query += %Q( category:"#{wwg_category.name}") if wwg_category

              if mkt_category
                query += %Q( category:"#{mkt_category.name}" )

                # nb: here we query for sub categories so that when looking at a
                # parent category we also include the items tied to sub
                # categories
                mkt_category.async_sub_categories.then do |sub_categories|
                  sub_categories.each { |sub_category| query += %Q( category:"#{sub_category.name}" ) }
                end
              end
            end
          end
        else
          Promise.resolve(true)
        end

        case verification_state
        when "verified"
          query += %Q( state:verified )
        when "unverified"
          query += %Q( state:unverified state:verification_pending_from_unverified)
        end

        promise.then do
          query
        end
      end

      def get_execute_query(query, variables, page)
        verification_state = variables[:verificationState]
        copilot_app = variables[:copilotApp]
        type = variables[:searchType]
        offers_free_trial = variables[:withFreeTrialsOnly]
        enterprise_compatible = variables[:enterpriseCompatibleOnly]
        items_per_page = variables[:items_per_page]
        is_dsa_compliant = variables[:isDsaCompliant]
        normalizer = lambda do |results|
          results.map! do |h|
            case h["_source"]["search_type"]
            when "marketplace_listing"
              Search::MarketplaceListingResultView.new(h)
            when "repository_action"
              Search::RepositoryActionResultView.new(h)
            when "azure_model"
              Search::AzureModelResultView.new(h)
            end
          end
        end


        # to be added : add more variables here
        Search::Queries::MarketplaceQuery.new(
          current_user: T.unsafe(self).current_user,
          phrase: query,
          type: type,
          offers_free_trial: offers_free_trial,
          enterprise_compatible: enterprise_compatible,
          verification_state: verification_state,
          copilot_app: copilot_app,
          context: "nographql-marketplace-search",
          highlight: ::Search::OffsetHighlighter.defaults,
          normalizer: normalizer,
          per_page: items_per_page,
          page: page,
          is_dsa_compliant: is_dsa_compliant,
        )
      end
    end
  end
end
