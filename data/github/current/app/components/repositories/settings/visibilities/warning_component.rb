# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Visibilities
      class WarningComponent < ApplicationComponent
        WARNING_ALERT = "Warning: this is a destructive action"
        WARNING_MESSAGES = {
          "private" => [
            "Making this repository private could permanently erase these counts by removing "\
              "stars and watchers associated to users that will no longer have access to this "\
              "repository:",
            "If you decide to make this repository public in the future, it will not be possible to "\
              "restore these stars and watchers and this will affect its repository rankings.",
            "Any custom Dependabot alert rules will be disabled "\
              "unless GitHub Advanced Security is enabled for this repository.",
            "Current forks will remain public and will be detached from this repository.",
          ],
          "internal" => [
            "Making this repository internal could permanently erase these counts by removing "\
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
      end
    end
  end
end
