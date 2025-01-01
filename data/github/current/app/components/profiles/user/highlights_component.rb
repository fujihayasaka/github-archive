# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class HighlightsComponent < ApplicationComponent
      HIGHLIGHT_MAPPING = {
        "developer_program_badge" => {
          component: Profiles::User::Highlights::DeveloperProgramHighlightComponent,
          condition: :show_developer_program_badge?,
        },
        "github_star" => {
          component: Profiles::User::Highlights::StarHighlightComponent,
          condition: :github_star?,
        },
        "pro_plan_badge" => {
          component: Profiles::User::Highlights::ProPlanHighlightComponent,
          condition: :has_pro_plan_badge?,
        },
        "bounty_hunter" => {
          component: Profiles::User::Highlights::BountyHunterHighlightComponent,
          condition: :bounty_hunter?,
        },
        "campus_expert" => {
          component: Profiles::User::Highlights::CampusExpertHighlightComponent,
          condition: :campus_expert?,
        },
        "discussion_answers_count" => {
          component: Profiles::User::Highlights::DiscussionAnswersCountHighlightComponent,
        },
        "advisory_credit_count" => {
          component: Profiles::User::Highlights::AdvisoryCreditCountHighlightComponent,
        },
      }.freeze
      ORDERED_HIGHLIGHTS = %w[
        developer_program_badge
        github_star
        pro_plan_badge
        bounty_hunter
        campus_expert
        discussion_answers_count
        advisory_credit_count
      ].freeze

      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      def render?
        bounty_hunter? ||
          campus_expert? ||
          (!GitHub.achievements_enabled? && discussion_answered_count > 0) ||
          github_star? ||
          global_advisory_credit_count > 0 ||
          has_pro_plan_badge? ||
          show_developer_program_badge?
      end

      def call
        content_tag(:div, class: "border-top color-border-muted pt-3 mt-3 d-none d-md-block") do
          safe_join(
            [
              content_tag(:h2, "Highlights", class: "h4 mb-2"),
              content_tag(:ul, displayable_highlights, class: "list-style-none"),
            ],
          )
        end
      end

      private

      attr_reader :profile_layout_data

      delegate(
        :bounty_hunter?,
        :campus_expert?,
        :discussion_answered_count,
        :github_star?,
        :global_advisory_credit_count,
        :has_pro_plan_badge?,
        :login_name,
        :show_developer_program_badge?,
        :user_is_viewer?,
        to: :profile_layout_data,
      )

      def displayable_highlights
        highlights = ORDERED_HIGHLIGHTS.map do |highlight|
          highlight_to_render = HIGHLIGHT_MAPPING[highlight]

          if highlight_to_render
            if condition = highlight_to_render[:condition]
              if send(condition)
                render highlight_to_render[:component].new(profile_layout_data: profile_layout_data)
              end
            else
              render highlight_to_render[:component].new(profile_layout_data: profile_layout_data)
            end
          end
        end

        safe_join(highlights)
      end
    end
  end
end
