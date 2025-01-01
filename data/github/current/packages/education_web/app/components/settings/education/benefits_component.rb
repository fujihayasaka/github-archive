# typed: strict
# frozen_string_literal: true

module Settings
  module Education
    class BenefitsComponent < ApplicationComponent
      sig { params(user: User, page: Integer, utm_source: T.nilable(String), utm_content: T.nilable(String)).void }
      def initialize(user:, page:, utm_source:, utm_content:)
        @user = user
        @page = page
        @utm_source = utm_source
        @utm_content = utm_content
      end

      sig { returns(String) }
      def call
        safe_join(
          [
            render(Primer::Beta::Subhead.new) do |component|
              component.with_heading(tag: :h2).with_content("GitHub Education")
            end,
            render(Billing::Settings::Education::OverviewComponent.new(
              user:,
              page:,
              utm_source:,
              utm_content:,
            )),
          ],
        )
      end

      private

      sig { returns(User) }
      attr_reader :user

      sig { returns(Integer) }
      attr_reader :page

      sig { returns(T.nilable(String)) }
      attr_reader :utm_source

      sig { returns(T.nilable(String)) }
      attr_reader :utm_content

      sig { returns(T::Boolean) }
      def render?
        feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
      end
    end
  end
end
