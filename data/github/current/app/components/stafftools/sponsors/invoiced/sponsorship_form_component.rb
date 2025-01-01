# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class SponsorshipFormComponent < ApplicationComponent
        # Form for creating/updating a sponsorship
        #
        # sponsor - User that is sponsoring
        # sponsorship_form_inputs - Stafftools::Sponsors::Invoiced::SponsorshipFormInputs with form data
        sig do
          params(
            sponsor: GitHubSponsors::Types::Sponsor,
            sponsorship_form_inputs: Stafftools::Sponsors::Invoiced::SponsorshipFormInputs,
          ).void
        end
        def initialize(sponsor:, sponsorship_form_inputs:)
          @sponsor = sponsor
          @sponsorship_form_inputs = sponsorship_form_inputs
        end

        private

        sig { returns(GitHubSponsors::Types::Sponsor) }
        attr_reader :sponsor

        sig { returns(Stafftools::Sponsors::Invoiced::SponsorshipFormInputs) }
        attr_reader :sponsorship_form_inputs

        sig { returns(T::Boolean) }
        def update?
          sponsorship_form_inputs.sponsorship_id.present?
        end

        sig { returns(String) }
        def form_action
          if update?
            stafftools_sponsors_invoiced_sponsor_sponsorship_path(sponsor, sponsorship_form_inputs.sponsorship_id)
          else
            stafftools_sponsors_invoiced_sponsor_sponsorships_path(sponsor)
          end
        end

        sig { returns(Symbol) }
        def form_method
          update? ? :patch : :post
        end

        sig { returns(String) }
        def button_text
          "#{update? ? "Update" : "Create"} sponsorship"
        end

        sig { returns(String) }
        def autocomplete_src
          stafftools_sponsors_approved_sponsorables_path
        end

        sig { returns(String) }
        def sponsors_update_email
          @sponsor.sponsors_update_email
        end

        sig { returns(Integer) }
        def start_year
          GitHub::Billing.today.year
        end

        sig { returns(Integer) }
        def end_year
          5.years.from_now.year
        end

        sig { returns(T::Boolean) }
        def render?
          return false unless GitHub.sponsors_enabled?
          logged_in?
        end

        sig { returns(T::Boolean) }
        def show_schedule_section?
          !update? || sponsorship_form_inputs.active_on.present?
        end

        sig { returns(T.nilable(String)) }
        def proration_message
          return if sponsor.can_skip_sponsorship_proration?
          "This sponsor is not able to skip proration, so this sponsorship will be prorated."
        end
      end
    end
  end
end
