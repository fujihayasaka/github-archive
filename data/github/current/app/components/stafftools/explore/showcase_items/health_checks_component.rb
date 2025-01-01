# typed: true
# frozen_string_literal: true

module Stafftools
  module Explore
    module ShowcaseItems
      class HealthChecksComponent < ApplicationComponent
        CHECKS = [
          :readme,
          :code_of_conduct,
          :contributing,
          :license,
          :description,
          :pr_or_issue_template,
          :security_policy,
        ]

        def initialize(community_profile:)
          @community_profile = community_profile
        end

        private

        attr_reader :community_profile

        def render?
          return false unless GitHub.showcase_enabled?

          community_profile.present?
        end

        def message
          # Check flag enablement with the repo owner instead of the current user so we don't penalize them for not
          # satisfying a check that they don't know about yet.
          if community_profile.health_percentage(repo_owner) == 100
            "This project meets minimum standards for a healthy community."
          else
            "When curating Showcases, we recommend that open source projects include these health files:"
          end
        end

        memoize def health_checks
          CHECKS.map do |check|
            HealthCheck.new(community_profile: community_profile, check: check)
          end
        end

        def repo_owner
          community_profile.repository&.owner
        end

        class HealthCheck
          attr_reader :community_profile, :check

          def initialize(community_profile:, check:)
            @community_profile = community_profile
            @check             = check
          end

          def name
            case check
            when :readme
              "README"
            when :code_of_conduct
              "Code of Conduct"
            when :pr_or_issue_template
              "Issue or Pull Request Template"
            else
              check.to_s.humanize
            end
          end

          def valid?
            return @valid if defined?(@valid)
            @valid = community_profile.send("#{check}?")
          end

          def octicon
            @octicon ||= Primer::Beta::Octicon.new(
              icon: valid? ? "check" : "x",
              color: valid? ? :success : :danger,
            )
          end
        end
      end
    end
  end
end
