# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Visibilities
      class WarningComponent < ApplicationComponent
        include Actions::RunnersClientHelper
        include Api::App::ActionsRunnerAdminHelper

        WARNING_ALERT = "Warning: this is a destructive action"
        WARNING_MESSAGES = {
          "private" => [
            "Making this repository private could erase these counts by removing "\
              "stars and watchers associated to users that will no longer have access to this "\
              "repository:",
            "Any custom Dependabot alert rules will be disabled "\
              "unless GitHub Advanced Security is enabled for this repository.",
            "Current forks will remain public and will be detached from this repository.",
          ],
          "internal" => [
            "Making this repository internal could erase these counts by removing "\
              "stars and watchers associated to users that will no longer have access to this "\
              "repository:",
            "All members of the enterprise will be given read access.",
            "Outside collaborators can no longer be added to forks unless they're added to the root.",
          ],
          "public" => [
            "",
            "The code will be visible to everyone who can visit %{github_url}",
            "Anyone can fork your repository.",
            "All push rulesets will be disabled.",
            "Your changes will be published as activity.",
            "Actions history and logs will be visible to everyone.",
          ],
        }.freeze

        def initialize(repository:, new_visibility:, stage:)
          @repository = repository
          @new_visibility = new_visibility
          @stage = stage
        end

        private

        attr_reader :repository, :new_visibility, :stage

        def stars_and_watchers
          content_tag(:div, class: "mb-3 text-center") do
            safe_join([
              content_tag(:span, class: "btn color-fg-danger cursor-default") do
                safe_join([
                  primer_octicon(:star, mr: 1, color: :danger),
                  helpers.number_with_delimiter(repository.stargazer_count),
                  content_tag(:span, "star".pluralize(repository.stargazer_count), class: "ml-1"),
                ])
              end,
              content_tag(:span, class: "btn color-fg-danger cursor-default ml-2") do
                safe_join([
                  primer_octicon(:eye, mr: 1, color: :danger),
                  helpers.number_with_delimiter(repository.watchers_count),
                  content_tag(:span, "watcher".pluralize(repository.watchers_count), class: "ml-1"),
                ])
              end,
            ])
          end
        end

        def warning_message
          case stage
          when 2
            second_warning_message
          when 3
            has_stars_or_watchers? ? third_warning_message : nil
          else
            nil
          end
        end

        def main_warning_message
          render(Primer::Beta::TimelineItem.new(
            classes: "repository-visibility-change-warning",
          )) do |component|
            component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
            component.with_body(font_weight: :bold) { WARNING_MESSAGES[new_visibility][0] }
          end
        end

        def second_warning_message
          other_messages = WARNING_MESSAGES[new_visibility][1..].map do |message|
            render(Primer::Beta::TimelineItem.new(
              p: 0,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body { message % { github_url: GitHub.url } }
            end
          end

          other_messages << advanced_security_configuration_warning if new_visibility != "public"

          # Add self-hosted runners warning when changing from non-public to public
          runners_warning = nil
          if repository.visibility != "public" && new_visibility == "public" && FeatureFlag.vexi.enabled?(:repositories_self_hosted_runner_visibility_warning, current_user, repository, repository.owner, repository.owner&.business, default: false)
            runners_warning = self_hosted_runners_warning
          end

          other_messages << runners_warning if runners_warning

          safe_join([
            content_tag(:hr),
            content_tag(:div, class: "mt-2") do
              safe_join([
                show_main_warning_and_counts? ? main_warning_message : nil,
                show_main_warning_and_counts? ? stars_and_watchers : nil,
              ] + other_messages)
            end,
          ])
        end

        def third_warning_message
          safe_join([
            if show_main_warning_and_counts?
              content_tag(:div, class: "flash mt-3 flash-warn") do
                safe_join([primer_octicon(:alert), WARNING_ALERT])
              end
            else
              nil
            end,
            show_main_warning_and_counts? ? main_warning_message : nil,
            show_main_warning_and_counts? ? stars_and_watchers : nil,
          ])
        end

        # Conditionally renders warnings about the consequences for advanced security products when a public repository is made non-public.
        def advanced_security_configuration_warning
          return nil unless repository.visibility == "public" && new_visibility != "public"
          warnings = []

          defaults = SecurityConfigurationDefault.find_for(target: repository.owner, visibility: :private)
          config = defaults.first&.security_configuration
          if config.nil?
            return security_products_will_be_disabled_warning
          end

          message = safe_join([
            "The",
            content_tag(:strong) do
              config.name
            end,
            "configuration will be applied as it is the default for new #{new_visibility} repositories."
          ], " ")

          warnings << render(Primer::Beta::TimelineItem.new(
            p: 0,
            condensed: true,
            classes: "repository-visibility-change-warning",
          )) do |component|
            component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
            component.with_body { message }
          end

          warnings << security_products_will_be_disabled_warning(default_config: config)
          warnings << security_products_will_be_billed_warning(default_config: config)

          warnings
        end

        # Conditionally renders a warning about security products that will be billed when a public repository is made non-public.
        def security_products_will_be_billed_warning(default_config: nil)
          warnings = []

          if repository.owner.advanced_security_products_bundled? && default_config.enable_ghas
            increased_usage = repository.owner.advanced_security_license.seat_usage_increase_if_enabled_for_repo(repository)
            if increased_usage.positive?
              message = safe_join([
                "This will consume",
                content_tag(:strong) do
                  "#{pluralize(increased_usage, "Advanced Security license")}."
                end,
              ], " ")
              warnings << render(Primer::Beta::TimelineItem.new(
                p: 0,
                ml: 6,
                condensed: true,
                classes: "repository-visibility-change-warning",
              )) do |component|
                component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
                component.with_body { message }
              end
            end
          end

          if !repository.owner.advanced_security_products_bundled? && default_config.secret_protection_sku_enabled
            increased_usage = repository.owner.secret_protection.seat_usage_increase_if_enabled_for_repo(repository)
            if increased_usage.positive?
              message = safe_join([
                "This will consume",
                content_tag(:strong) do
                  "#{pluralize(increased_usage, "Secret Protection license")}."
                end,
              ], " ")
              warnings << render(Primer::Beta::TimelineItem.new(
                p: 0,
                ml: 6,
                condensed: true,
                classes: "repository-visibility-change-warning",
              )) do |component|
                component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
                component.with_body { message }
              end
            end
          end

          if !repository.owner.advanced_security_products_bundled? && default_config.code_security_sku_enabled
            increased_usage = repository.owner.code_security.seat_usage_increase_if_enabled_for_repo(repository)
            if increased_usage.positive?
              message = safe_join([
                "This will consume",
                content_tag(:strong) do
                  "#{pluralize(increased_usage, "Code Security license")}."
                end,
              ], " ")
              warnings << render(Primer::Beta::TimelineItem.new(
                p: 0,
                ml: 6,
                condensed: true,
                classes: "repository-visibility-change-warning",
              )) do |component|
                component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
                component.with_body { message }
              end
            end
          end

          warnings
        end

        # Conditionally renders a warning about security products that will be disabled when a public repository is made non-public.
        def security_products_will_be_disabled_warning(default_config: nil)
          warnings = []

          # If there is a default config, messages about security products to be disabled will be
          # indented as sub-items under the "security configuration will be applied" message.
          indentation = default_config.nil? ? 3 : 6

          advanced_security_will_be_disabled = repository.owner.advanced_security_products_bundled? && !default_config&.enable_ghas
          code_security_will_be_disabled = !repository.owner.advanced_security_products_bundled? && !default_config&.code_security_sku_enabled
          secret_protection_will_be_disabled = !repository.owner.advanced_security_products_bundled? && !default_config&.secret_protection_sku_enabled

          if advanced_security_will_be_disabled
            warnings << render(Primer::Beta::TimelineItem.new(
              p: 0,
              ml: indentation,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body do
                "Advanced Security will be disabled."
              end
            end
          end

          if code_security_will_be_disabled && secret_protection_will_be_disabled
            warnings << render(Primer::Beta::TimelineItem.new(
              p: 0,
              ml: indentation,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body do
                "Secret Protection and Code Security will be disabled."
              end
            end
          elsif secret_protection_will_be_disabled
            warnings << render(Primer::Beta::TimelineItem.new(
              p: 0,
              ml: indentation,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body do
                "Secret Protection will be disabled."
              end
            end
          elsif code_security_will_be_disabled
            warnings << render(Primer::Beta::TimelineItem.new(
              p: 0,
              ml: indentation,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body do
                "Code Security will be disabled."
              end
            end
          end

          warnings
        end

        memoize def has_stars_or_watchers?
          repository.stargazer_count.positive? || repository.watchers_count.positive?
        end

        memoize def show_main_warning_and_counts?
          new_visibility != "public" && has_stars_or_watchers?
        end

        # Conditionally renders a warning about self-hosted runners when making a repository public.
        def self_hosted_runners_warning
          # Only check for self-hosted runners when changing to public visibility
          return nil unless repository.visibility != "public" && new_visibility == "public"

          # Feature flag check
          return nil unless FeatureFlag.vexi.enabled?(:repositories_self_hosted_runner_visibility_warning, current_user, repository, repository.owner, repository.owner&.business, default: false)

          has_runners = has_self_hosted_runners?

          # Handle different runner check results
          case has_runners
          when false
            return nil
          when :unknown
            # Show uncertainty warning when we couldn't determine runner status
            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.warning_displayed",
              tags: ["warning_type:uncertainty", "reason:unknown_status"])

            GitHub.logger.info("RepositoryVisibilityWarning: Uncertainty warning displayed to user", {
              "gh.request_id" => GitHub.context&.[](:request_id),
              "gh.repository.id" => repository&.id,
              "gh.repository.owner.id" => repository&.owner&.id,
              "gh.repository.owner.type" => repository&.owner&.class&.name,
              "warning_type" => "uncertainty",
              "reason" => "unknown_status",
              "message_text" => "may contain self-hosted runners",
              "code.function" => "self_hosted_runners_warning",
              "code.namespace" => "Repositories::Settings::Visibilities::WarningComponent"
            })

            message = safe_join([
              "This repository may contain self-hosted runners. Using self-hosted runners in public repositories is not recommended. Forks of your public repository can potentially run dangerous code on your self-hosted runner by creating a pull request.",
              content_tag(:a, "Learn more about security hardening for self-hosted runners",
                href: "#{GitHub.help_url}/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#self-hosted-runner-security-with-public-repositories",
                class: "Link--inTextBlock")
            ], " ")

            return render(Primer::Beta::TimelineItem.new(
              p: 0,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :attention, icon: :"alert-fill")
              component.with_body { message }
            end
          when true
            # Confirmed runners - show definitive warning (from API call)
            reason = "runners_confirmed"
          else
            return nil
          end

          # Show definitive warning
          if has_runners == true
            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.warning_displayed",
              tags: ["warning_type:definitive", "reason:#{reason}"])

            GitHub.logger.info("RepositoryVisibilityWarning: Definitive warning displayed to user", {
              "gh.request_id" => GitHub.context&.[](:request_id),
              "gh.repository.id" => repository&.id,
              "gh.repository.owner.id" => repository&.owner&.id,
              "gh.repository.owner.type" => repository&.owner&.class&.name,
              "warning_type" => "definitive",
              "reason" => reason,
              "message_text" => "contains self-hosted runners",
              "code.function" => "self_hosted_runners_warning",
              "code.namespace" => "Repositories::Settings::Visibilities::WarningComponent"
            })

            message = safe_join([
              "This repository contains self-hosted runners. Using self-hosted runners in public repositories is not recommended. Forks of your public repository can potentially run dangerous code on your self-hosted runner by creating a pull request.",
              content_tag(:a, "Learn more about security hardening for self-hosted runners",
                href: "#{GitHub.help_url}/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#self-hosted-runner-security-with-public-repositories",
                class: "Link--inTextBlock")
            ], " ")
          else
            return nil
          end

          render(Primer::Beta::TimelineItem.new(
            p: 0,
            condensed: true,
            classes: "repository-visibility-change-warning",
          )) do |component|
            component.with_badge(bg: :transparent, color: :attention, icon: :"alert-fill")
            component.with_body { message }
          end
        end

        memoize def has_self_hosted_runners?
          return false unless repository&.visibility != "public" && new_visibility == "public" && FeatureFlag.vexi.enabled?(:repositories_self_hosted_runner_visibility_warning, current_user, repository, repository&.owner, repository&.owner&.business, default: false)

          begin
            # Check if repository has any self-hosted runners using list_runners_helper
            # Only fetch 1 runner since we just need to check if any exist
            start_time = GitHub::Dogstats.monotonic_time

            # Use custom clients with 2-second timeouts for this specific use case since Timeout.timeout is not reliable
            resp = list_runners_helper_with_short_timeout(repository, use_runner_admin: use_runner_admin?(repository, is_ui_read: true), per_page: 1)
            elapsed_ms = GitHub::Dogstats.duration(start_time)

            GitHub.dogstats.distribution("repositories.settings.visibilities.warning_component.list_runners_duration", elapsed_ms,
              tags: ["result:success"])

            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.list_runners_calls",
              tags: ["result:success"])

            GitHub.logger.info("RepositoryVisibilityWarning: Runner API call completed", {
              "gh.request_id" => GitHub.context&.[](:request_id),
              "gh.repository.id" => repository&.id,
              "gh.repository.owner.id" => repository&.owner&.id,
              "gh.repository.owner.type" => repository&.owner&.class&.name,
              "code.function" => "has_self_hosted_runners?",
              "code.namespace" => "Repositories::Settings::Visibilities::WarningComponent",
              "gh.repositories.settings.visibilities.warning_component.list_runners_duration_ms" => elapsed_ms,
              "result" => "success"
            })

            # If the API call failed, return :unknown to show uncertainty warning
            unless resp.call_succeeded?
              GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.uncertainty_warning_shown",
                tags: ["reason:api_call_failed", "status:#{resp.status}"])

              GitHub.logger.warn("RepositoryVisibilityWarning: API call failed - showing uncertainty warning", {
                "gh.request_id" => GitHub.context&.[](:request_id),
                "gh.repository.id" => repository&.id,
                "gh.repository.owner.id" => repository&.owner&.id,
                "gh.repository.owner.type" => repository&.owner&.class&.name,
                "code.function" => "has_self_hosted_runners?",
                "code.namespace" => "Repositories::Settings::Visibilities::WarningComponent",
                "gh.repositories.settings.visibilities.warning_component.list_runners_duration_ms" => elapsed_ms,
                "response.status" => resp.status,
                "response.call_succeeded" => resp.call_succeeded,
                "response.value" => resp.value.inspect,
                "response.options" => resp.options,
                "warning_decision" => "uncertainty_on_failed_call"
              })

              return :unknown
            end

            total = resp.value&.total_runners || 0
            total > 0

          rescue Actions::ServiceError, Scientist::Experiment::MismatchError, Net::OpenTimeout, Net::ReadTimeout, Faraday::TimeoutError, StandardError => e
            # Record failed API call timing and error details
            elapsed_ms = GitHub::Dogstats.duration(start_time)

            # Simple error type classification for monitoring
            error_type = case e
            when Actions::ServiceError
              if e.respond_to?(:status)
                "status_#{e.status}"
              else
                "service_error"
              end
            when Net::OpenTimeout, Net::ReadTimeout, Faraday::TimeoutError
              "timeout"
            when Scientist::Experiment::MismatchError
              "experiment_mismatch"
            when Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
              "network_error"
            when OpenSSL::SSL::SSLError
              "ssl_error"
            when JSON::ParserError
              "json_error"
            when NoMethodError
              "no_method_error"
            else
              "unknown_error"
            end

            GitHub.dogstats.distribution("repositories.settings.visibilities.warning_component.list_runners_duration", elapsed_ms,
              tags: ["result:error", "error_type:#{error_type}"])

            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.list_runners_calls",
              tags: ["result:error", "error_type:#{error_type}"])

            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.list_runners_errors",
              tags: ["error_type:#{error_type}"])

            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.runner_check_failure",
              tags: ["error_type:#{e.class.name}"])

            GitHub.dogstats.increment("repositories.settings.visibilities.warning_component.uncertainty_warning_shown",
              tags: ["error_type:#{e.class.name}", "reason:api_failure"])

            GitHub.logger.warn("RepositoryVisibilityWarning: Runner API call failed - showing uncertainty warning", {
              "gh.request_id" => GitHub.context&.[](:request_id),
              "gh.repository.id" => repository&.id,
              "gh.repository.owner.id" => repository&.owner&.id,
              "gh.repository.owner.type" => repository&.owner&.class&.name,
              "error.class" => e.class.name,
              "error.message" => e.message,
              "error.status" => (e.is_a?(Actions::ServiceError) && e.respond_to?(:status) ? e.status : nil),
              "code.function" => "has_self_hosted_runners?",
              "code.namespace" => "Repositories::Settings::Visibilities::WarningComponent",
              "gh.repositories.settings.visibilities.warning_component.list_runners_duration_ms" => elapsed_ms,
              "error_type" => error_type,
              "result" => "error",
              "warning_decision" => "uncertainty_on_error"
            })

            # Return :unknown to trigger "may contain" uncertainty warning
            :unknown
          end
        end
      end
    end
  end
end
