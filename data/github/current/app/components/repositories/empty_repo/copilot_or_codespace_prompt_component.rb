# typed: strict
# frozen_string_literal: true

module Repositories
  module EmptyRepo
    # Thin renderer for the primary (Copilot/Codespaces) onboarding card on the
    # empty-repo state. Variant selection, copy, and URLs live in
    # `Repositories::EmptyRepo::OnboardingPrompts`; this component renders
    # whatever descriptor the resolver returns.
    class CopilotOrCodespacePromptComponent < ApplicationComponent
      include MemberFeatureRequestsHelper

      include ApplicationComponent::Rescuable
      rescue_from StandardError, with: :nothing

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns T.nilable(Repository) }
      attr_reader :repository

      sig { returns T.nilable(User) }
      attr_reader :user

      sig do
        params(
          user_can_push: T::Boolean,
          user: T.nilable(User),
          copilot_user: T.nilable(Copilot::User),
          repository: T.nilable(Repository),
          descriptor: T.nilable(T::Hash[Symbol, T.untyped]),
          system_arguments: Primer::SystemArgumentsValue
        ).void
      end
      def initialize(user_can_push:, user: nil, copilot_user: nil, repository: nil, descriptor: nil, **system_arguments)
        @user_can_push = user_can_push
        @user = T.let(user, T.nilable(User))
        @copilot_user = T.let(copilot_user, T.nilable(Copilot::User))
        @repository = T.let(repository, T.nilable(Repository))
        @descriptor = T.let(descriptor, T.nilable(T::Hash[Symbol, T.untyped]))
        @system_arguments = system_arguments
      end

      sig { returns T::Boolean }
      def render?
        return false unless @repository
        !descriptor.nil?
      end

      sig { returns T.nilable(T::Hash[Symbol, T.untyped]) }
      def descriptor
        return @descriptor if @descriptor
        @resolved_descriptor ||= T.let(resolver.primary_prompt, T.nilable(T::Hash[Symbol, T.untyped]))
      end

      sig { returns String }
      def variant
        descriptor&.dig(:variant).to_s
      end

      sig { returns T.nilable(Symbol) }
      def icon
        descriptor&.dig(:icon)
      end

      sig { returns String }
      def title
        descriptor&.dig(:title).to_s
      end

      sig { returns String }
      def description
        descriptor&.dig(:description).to_s
      end

      sig { returns String }
      def button_label
        descriptor&.dig(:button_label).to_s
      end

      sig { returns String }
      def href
        descriptor&.dig(:href).to_s
      end

      sig { returns String }
      def test_selector
        case variant
        when "copilot-org-admin"   then "copilot-prompt-org-admin"
        when "copilot-org-member"  then "copilot-prompt-org-member"
        when "copilot-individual"  then "copilot-prompt-individual"
        when "codespaces"          then "create-codespace-prompt"
        else ""
        end
      end

      sig { returns T::Hash[String, String] }
      def analytics_data
        analytics = descriptor&.dig(:analytics)
        return {} if analytics.nil? || variant == "copilot-org-member"
        analytics_click_attributes(**analytics)
      end

      sig { returns T::Hash[String, String] }
      def member_request_analytics
        analytics = descriptor&.dig(:analytics)
        return {} unless analytics
        analytics_click_attributes(**analytics)
      end

      sig { returns T.nilable(Organization) }
      def member_request_organization
        descriptor&.dig(:organization)
      end

      sig { returns T.nilable(MemberFeatureRequest::Feature) }
      def member_request_feature
        descriptor&.dig(:feature)
      end

      sig { returns T.nilable(User) }
      def member_request_requester
        descriptor&.dig(:requester)
      end

      private

      sig { returns Repositories::EmptyRepo::OnboardingPrompts }
      memoize def resolver
        T.must(T.let(
          Repositories::EmptyRepo::OnboardingPrompts.new(
            repository: @repository,
            current_user: @user,
            user_can_push: @user_can_push,
            copilot_user: @copilot_user,
          ),
          T.nilable(Repositories::EmptyRepo::OnboardingPrompts),
        ))
      end

      sig { returns T::Boolean }
      def user_part_of_org?
        !!@user&.member_or_billing_manager_for_any_organization?
      end
    end
  end
end
