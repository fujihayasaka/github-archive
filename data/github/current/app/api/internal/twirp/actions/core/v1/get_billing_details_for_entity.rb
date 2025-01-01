# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetBillingDetailsForEntity
        attr_reader :entity_id, :product_sku

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @entity_id = request.entity_id.global_id
          @product_sku = request.product_sku
          ## we initially set this to nil, but if the request is for a repo, we will set it to the repo value
          @repo = nil
        end

        def call
          return Twirp::Error.not_found("entity does not exist", argument: "entity_id") unless entity
          return Twirp::Error.not_found("product sku is a required parameter", argument: "product_sku") unless product_sku

          ## temporary SKU mapping for basic or custom runners
          ## see https://github.com/github/c2c-actions/blob/main/docs/adrs/5788-pre-job-check.md#dotcom-changes
          is_basic_sku = list_of_basic_skus.include?(product_sku.to_sym)
          tags = ["product_sku:#{product_sku}", "is_basic_sku:#{is_basic_sku}", "entity_type:#{entity.class.name}"]

          GitHub.logger.info("Getting billing details for Actions entities", {
            "actions.usage.product_sku" => product_sku.to_sym,
            "actions.usage.is_basic_sku" => is_basic_sku,
            "actions.usage.entity_type" => entity.class.name
          })

          actions_permission = Billing::ActionsPermission.new(entity)

          is_spammy = entity.spammy?
          is_public_repository = is_public_repository?
          is_larger_runner = is_larger_runner?(product_sku)

          is_usage_allowed = actions_permission.usage_allowed?(public: is_public_repository, sku: product_sku)
          is_storage_allowed = actions_permission.storage_allowed?(public: is_public_repository)

          tags += ["spammy:#{is_spammy}", "public_repository:#{is_public_repository}", "larger_runner:#{is_larger_runner}", "usage_allowed:#{is_usage_allowed}", "storage_allowed:#{is_storage_allowed}"]
          GitHub.dogstats.increment("actions.twirp.get_billing_details_for_entity", tags: tags)

          {
            is_actions_usage_allowed: is_usage_allowed,
            is_actions_storage_allowed: is_storage_allowed,
            is_owner_spammy: is_spammy,
          }
        end

        private

        # self-hosted runner = empty product_sku for now (eventually we want to have an explicit sku for this)
        # basic runner = one of the 3 in list_of_basic_skus function below
        # larger runner = product_sku not in list_of_basic_skus and not empty
        def is_larger_runner?(product_sku)
          if product_sku.present? && !list_of_basic_skus.include?(product_sku.to_sym)
            return true
          end
          false
        end

        def is_public_repository?
          if @repo.nil?
            return false
          end
          @repo.public?
        end

        def decoded_id
          @decoded_id ||= Platform::Helpers::NodeIdentification.from_global_id(entity_id)
        end

        def list_of_basic_skus
          [:linux, :windows, :macos]
        end

        def entity
          return @entity if defined? @entity
          @entity ||= begin
            case decoded_id.first
            when "Enterprise"
              return Business.find_by(id: decoded_id.last)
            when "Organization"
              return Organization.find_by(id: decoded_id.last)
            when "Repository"
              repo = Repository.find_by(id: decoded_id.last)
              if !repo.nil?
                @repo = repo
                repo.owner
              end
            else
              return nil
            end
          end
        end
      end
    end
  end
end
