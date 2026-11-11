# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        class TemplateResourceDetails
          include GitHub::Memoizer
          include Site::Contentful::Helpers::CacheHelper

          # Query for fetching all Resource Details entries (no concept filter)
          ResourceDetailsQuery = T.let(Client.parse(<<-'GRAPHQL'), T.untyped)
            query($locale: String!, $limit: Int, $skip: Int, $resourceType: String!) {
              templateResourceDetailsCollection(
                locale: $locale,
                limit: $limit,
                skip: $skip,
                where: {
                  resourceType: $resourceType
                }
              ) {
                total
                items {
                  featuredImage {
                    description
                    url
                  }
                  hero {
                    heading
                    image {
                      description
                      url
                    }
                  }
                  # Ensure paths are fetched from the en-us locale, regardless of the user's selected content locale.
                  linkedFrom(allowedLocales: ["en-US"]) {
                    containerPageCollection(locale: "en-US") {
                      items {
                        path
                      }
                    }
                  }
                  lede {
                    json
                  }
                }
              }
            }
          GRAPHQL

          # Query for fetching Resource Details entries filtered by taxonomy concept IDs
          ResourceDetailsByConceptQuery = T.let(Client.parse(<<-'GRAPHQL'), T.untyped)
            query($locale: String!, $limit: Int, $skip: Int, $resourceType: String!, $conceptIds: [String!]!) {
              templateResourceDetailsCollection(
                locale: $locale,
                limit: $limit,
                skip: $skip,
                where: {
                  resourceType: $resourceType,
                  contentfulMetadata: {
                    concepts: {
                      id_contains_some: $conceptIds
                    }
                  }
                }
              ) {
                total
                items {
                  featuredImage {
                    description
                    url
                  }
                  hero {
                    heading
                    image {
                      description
                      url
                    }
                  }
                  linkedFrom(allowedLocales: ["en-US"]) {
                    containerPageCollection(locale: "en-US") {
                      items {
                        path
                      }
                    }
                  }
                  lede {
                    json
                  }
                }
              }
            }
          GRAPHQL

          sig do
            params(
              locale: String,
              resource_type: String,
              concept_ids: T::Array[String],
              limit: Integer,
              skip: Integer
            ).void
          end
          def initialize(locale: "en-US", resource_type: "Article", concept_ids: [], limit: 12, skip: 0)
            @locale = T.let(locale, String)
            @resource_type = T.let(resource_type, String)
            @concept_ids = T.let(Array(concept_ids).reject(&:blank?), T::Array[String])
            @limit = T.let(limit, Integer)
            @skip = T.let(skip, Integer)
            @current_cache_key = T.let(nil, T.nilable(Site::Contentful::Page::CacheKey))
          end

          # Returns the cache key for the current query parameters
          sig { override.returns(Site::Contentful::Page::CacheKey) }
          def cache_key
            @current_cache_key || build_cache_key(@concept_ids, @limit, @skip)
          end

          # Revalidate method for compatibility with RevalidatePageJob
          sig { returns({ total: Integer, items: T::Array[T::Hash[String, T.untyped]] }) }
          def revalidate
            @current_cache_key = build_cache_key(@concept_ids, @limit, @skip)
            fetch_and_cache_resources(@concept_ids, @limit, @skip)
          end

          sig do
            params(
              concept_ids: T.nilable(T.any(String, T::Array[String])),
              limit: Integer,
              skip: Integer
            ).returns({
              total: Integer,
              items: T::Array[T::Hash[String, T.untyped]]
            })
          end
          def resources_by_concept(concept_ids: nil, limit: 12, skip: 0)
            ids_array = Array(concept_ids).reject(&:blank?)

            # Set the cache key based on query parameters
            @current_cache_key = build_cache_key(ids_array, limit, skip)

            # Try to get from cache first
            cached = page_cached_data
            if cached.present?
              return {
                total: cached[:total] || 0,
                items: cached[:items] || []
              }
            end

            # Cache miss - fetch from API and cache the result
            fetch_and_cache_resources(ids_array, limit, skip)
          end

          # Async revalidation method for background cache refresh
          sig do
            params(
              concept_ids: T.nilable(T.any(String, T::Array[String])),
              limit: Integer,
              skip: Integer
            ).void
          end
          def async_revalidate(concept_ids: nil, limit: 12, skip: 0)
            ids_array = Array(concept_ids).reject(&:blank?)
            @current_cache_key = build_cache_key(ids_array, limit, skip)
            fetch_and_cache_resources(ids_array, limit, skip)
          end

          private

          sig { params(concept_ids: T::Array[String], limit: Integer, skip: Integer).returns(Site::Contentful::Page::CacheKey) }
          def build_cache_key(concept_ids, limit, skip)
            params = {
              resource_type: @resource_type,
              limit: limit.to_s,
              skip: skip.to_s,
            }
            params[:concepts] = concept_ids.sort.join(",") if concept_ids.any?

            Site::Contentful::Page::CacheKey.new(
              base: "site.contentful.marketing.graphql.template_resource_details",
              locale: @locale,
              path: concept_ids.any? ? "by_concept" : "all",
              version: 2,
              user_provided_parameters: params,
            )
          end

          sig do
            params(
              ids_array: T::Array[String],
              limit: Integer,
              skip: Integer
            ).returns({
              total: Integer,
              items: T::Array[T::Hash[String, T.untyped]]
            })
          end
          def fetch_and_cache_resources(ids_array, limit, skip)
            # Use the appropriate query based on whether concept_ids are provided
            if ids_array.any?
              variables = { locale: @locale, limit: limit, skip: skip, resourceType: @resource_type, conceptIds: ids_array }
              response = Client.query(ResourceDetailsByConceptQuery, variables:)
            else
              variables = { locale: @locale, limit: limit, skip: skip, resourceType: @resource_type }
              response = Client.query(ResourceDetailsQuery, variables:)
            end

            if response.errors.any?
              GitHub.logger.error(
                "Error fetching resource details from Contentful GraphQL",
                errors: response.errors.messages.to_h,
                concept_ids: ids_array
              )
              return { total: 0, items: [] }
            end

            total = response.data&.template_resource_details_collection&.total || 0
            items = (response.data&.template_resource_details_collection&.items || []).filter_map do |resource|
              data = resource.to_h
              path = data.dig("linkedFrom", "containerPageCollection", "items", 0, "path")
              # Skip resources without a valid path since they can't be navigated to
              next if path.blank?

              image = data["featuredImage"] || data.dig("hero", "image")
              {
                "heading" => data.dig("hero", "heading"),
                "image" => image,
                "path" => path,
                "description" => data.dig("lede", "json")
              }
            end

            result = { total:, items: }

            # Cache the result
            save_page_data_in_cache(result)

            result
          end
        end
      end
    end
  end
end
