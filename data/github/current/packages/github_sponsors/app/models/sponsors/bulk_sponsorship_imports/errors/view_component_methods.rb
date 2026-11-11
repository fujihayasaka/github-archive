# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      module ViewComponentMethods
        extend T::Helpers

        include GitHub::Memoizer
        include ViewComponent::InlineTemplate

        requires_ancestor { ApplicationComponent }

        abstract!

        sig { params(base: T.class_of(ApplicationComponent)).void }
        def self.included(base)
          base.erb_template <<~ERB
            <%= render Primer::Alpha::Banner.new(
              icon: :info,
              dismiss_scheme: :remove,
              mb: 3,
              test_selector: test_selector,
            ) do %>
              <%= error_message %><br>
              <% errored_login_messages.each do |login_with_message| %>
                <%= login_with_message %><br>
              <% end %>
            <% end %>
          ERB
        end

        # errored_rows - Array of Sponsors::BulkSponsorshipRow representing the
        #   rows from an imported CSV.
        # test_selector - String to use as the test selector for the banner.
        sig { overridable.params(errored_rows: T::Array[BulkSponsorshipRow]).void }
        def initialize(errored_rows:)
          @errored_rows = errored_rows
        end

        protected

        sig { returns T::Array[BulkSponsorshipRow] }
        attr_reader :errored_rows

        sig { overridable.returns(T::Array[String]) }
        memoize def sponsorable_logins
          errored_rows.map { |row| row.sponsorable&.display_login || row.sponsorable_login }
        end

        sig { returns Integer }
        def sponsorable_logins_count
          sponsorable_logins.count
        end

        sig { abstract.returns(String) }
        def test_selector; end

        sig { abstract.returns(String) }
        def error_message; end

        sig { overridable.returns(T::Array[String]) }
        def errored_login_messages
          sponsorable_logins.map { |login| "@#{login}" }
        end

        sig { returns GitHubSponsors::Types::Sponsor }
        memoize def sponsor
          errored_row = T.must_because(errored_rows.first) { "#render? ensures non-nil" }
          errored_row.sponsor # sponsor will be the same for every row
        end

        private

        sig { returns T::Boolean }
        def render?
          errored_rows.present? && GitHub.sponsors_enabled? && logged_in?
        end
      end
    end
  end
end
