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
          when SecretScanningControllerHelper::BLANKSLATE_NO_ALERTS_ENABLE_ON_ALL_REPOS
            "There aren’t any secrets found yet"
          when SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_OR_CLOSED_SECRETS
            "There aren’t any secrets found yet"
          when SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_SECRETS
            "All caught up!"
          else
            "No secrets found"
          end
        end

        def blankslate_icon
          if @blankslate == SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_SECRETS
            :"shield-check"
          elsif @blankslate == SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_OR_CLOSED_SECRETS
            :shield
          else
            :key
          end
        end

        def icon_animation_class
          return unless animate_icon?

          "secret-scanning-shield-animate"
        end

        def animate_icon?
          @blankslate == SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_SECRETS
        end

        def test_selector
          if QUERY_PARSER.has_duplicate_qualifiers?(@query)
            "secret-scanning-alert-centric-views-blankslates-table-body-component-duplicate-qualifier"
          else
            case @blankslate
            when SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_SECRETS
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-open-secrets"
            when SecretScanningControllerHelper::BLANKSLATE_NO_OPEN_OR_CLOSED_SECRETS
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-open-or-closed-secrets"
            when SecretScanningControllerHelper::BLANKSLATE_NO_MATCHES
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-matches"
            when SecretScanningControllerHelper::BLANKSLATE_INVALID_QUERY
              "secret-scanning-alert-centric-views-blankslates-table-body-component-invalid-query"
            when SecretScanningControllerHelper::BLANKSLATE_NO_ALERTS_ENABLE_ON_ALL_REPOS
              "secret-scanning-alert-centric-views-blankslates-table-body-component-no-alerts-enable-on-all-repos"
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

        def get_security_configurations_url
          if @scope.is_a?(Business)
            "/enterprises/#{@scope.slug}/settings/security_analysis"
          else
            "/organizations/#{@scope.display_login}/settings/security_products"
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

        def view_path
          if @scope.is_a?(Business)
            "/enterprises/#{@scope.slug}/security/alerts/secret-scanning"
          else
            "/orgs/#{@scope.display_login}/security/alerts/secret-scanning"
          end
        end

        def enable_on_all_repos_cta_label
          "Manage security configurations"
        end

        def enable_on_all_repos_hydro_click_data
          helpers.hydro_click_tracking_attributes("security_center.blankslate.click", {
            label: enable_on_all_repos_cta_label,
            target_url: get_security_configurations_url,
            view: view_path
          })
        end
      end
    end
  end
end
