# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    module Blankslates
      class TableBodyComponent < ApplicationComponent
        QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

        def initialize(blankslate: nil, query: "", scope: nil)
          @blankslate = blankslate
          @query = query
          @scope = scope
        end

        def blankslate_title
          case @blankslate
          when SecretScanningControllerHelper::BLANKSLATE_INVALID_QUERY
            "Invalid query."
          else
            "No secrets found."
          end
        end

        def test_selector
          if QUERY_PARSER.has_duplicate_qualifiers?(@query)
            "secret-scanning-alert-centric-views-blankslates-table-body-component-duplicate-qualifier"
          else
            case @blankslate
            when SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_SECRETS
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-open-secrets"
            when SecretScanningControllerHelper::BLANKSLATE_NO_MATCHES
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-matches"
            when SecretScanningControllerHelper::BLANKSLATE_INVALID_QUERY
              "secret-scanning-alert-centric-views-blankslates-table-body-component-invalid-query"
            end
          end
        end

        def get_security_analysis_settings_url
          if @scope.is_a?(Business)
            "/enterprises/#{@scope.slug}/settings/security_analysis"
          elsif @scope.is_a?(Organization)
            "/organizations/#{@scope}/settings/security_analysis"
          else
            "/#{@scope.name_with_display_owner}/settings/security_analysis"
          end
        end

        def humanized_scope
          if @scope.is_a?(Business)
            "enterprise"
          elsif @scope.is_a?(Organization)
            "organization"
          else
            "repository"
          end
        end
      end
    end
  end
end
