# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    module Zuora
      class HostedPagesController < StafftoolsController
        before_action :dotcom_required

        depends_on_clusters ApplicationRecord::Mysql1,
          ApplicationRecord::Collab,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Billing,
          ApplicationRecord::Ballast,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Repositories,
          ApplicationRecord::Configurations,
          only: [:index]

        depends_on_clusters ApplicationRecord::Copilot,
          only: [:index],
          optional: true

        def index
          zuora_pages = fetch_hosted_pages
          config_mappings = build_config_mappings(zuora_pages)

          render "stafftools/billing/zuora/hosted_pages/index", locals: {
            zuora_pages: zuora_pages,
            config_mappings: config_mappings,
            zuora_ui_base_url: zuora_ui_base_url,
            error: nil,
          }
        rescue => e
          Failbot.report(e)
          render "stafftools/billing/zuora/hosted_pages/index", locals: {
            zuora_pages: [],
            config_mappings: [],
            zuora_ui_base_url: zuora_ui_base_url,
            error: e.message,
          }
        end

        private

        # Derives the Zuora UI base URL from the configured REST server URL.
        # e.g. "https://rest.zuora.com" → "https://zuora.com"
        #      "https://rest.apisandbox.zuora.com" → "https://apisandbox.zuora.com"
        def zuora_ui_base_url
          uri = URI.parse(GitHub.zuora_rest_server)
          host = uri.host.to_s.sub(/\Arest\./, "")
          "#{uri.scheme}://#{host}"
        end

        # Fetches hosted pages from the Zuora API (all versions for maximum info)
        def fetch_hosted_pages
          response = GitHub.zuorest_client.get("/v1/hostedpages") # rubocop:disable GitHub/ZuoraRestVerbs
          body = response.respond_to?(:body) ? response.body : response

          if body.is_a?(Hash) && body["hostedpages"]
            body["hostedpages"]
          elsif body.is_a?(Hash) && body[:hostedpages]
            body[:hostedpages]
          else
            []
          end
        end

        # Builds a mapping between GitHub config attributes and Zuora hosted pages
        # using the central registry in HostedPaymentsPage
        def build_config_mappings(zuora_pages)
          zuora_pages_by_id = zuora_pages.each_with_object({}) do |page, hash|
            page_id = page["pageId"] || page[:pageId]
            hash[page_id] = page if page_id
          end

          ::Billing::Zuora::HostedPaymentsPage.all_page_configs.map do |entry|
            zuora_page = zuora_pages_by_id[entry[:page_id]]

            entry.merge(
              zuora_page: zuora_page,
              status: zuora_page ? :mapped : :unmapped,
            )
          end
        end
      end
    end
  end
end
