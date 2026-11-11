# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UnlicensedUserSettingsComponent < ApplicationComponent
      sig do
        params(
          copilot_user: Copilot::User,
          submit_path: T.nilable(String),
          changed_settings: T.nilable(T::Hash[Symbol, T::Boolean])
        ).void
      end
      def initialize(copilot_user:, submit_path: nil, changed_settings: nil)
        @copilot_user = copilot_user
        @submit_path = submit_path
        @changed_settings = T.let(changed_settings || {}, T::Hash[Symbol, T::Boolean])
      end

      sig { returns(T::Boolean) }
      def render?
        @copilot_user.feature_flag_enabled?(:copilot_show_unlicensed_policies, default: false)
      end

      sig { params(value: Symbol).returns(T::Boolean) }
      def changed?(value)
        !!@changed_settings.fetch(value, false)
      end

      sig { params(url: String, copy: String).returns(String) }
      def inline_docs_link(url, copy)
        link = render(Primer::Beta::Link.new(href: url, classes: "Link--inTextBlock")) { copy }
        link.html_safe # rubocop:disable Rails/OutputSafety
      end
    end
  end
end
