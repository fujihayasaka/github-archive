# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorships::BreadcrumbComponent < ApplicationComponent
  extend T::Sig

  class Page < T::Enum
    enums do
      SelectFrequency = new("Get started")
      Import = new("Import")
      Review = new("Review")
      Checkout = new("Checkout")
    end
  end

  # frequency - choose from :recurring or :one_time
  sig do
    params(
      page: Page,
      sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
      frequency: T.nilable(Symbol),
      system_arguments: T.untyped
    ).void
  end
  def initialize(page:, sponsor:, frequency: nil, **system_arguments)
    @page = page
    @sponsor = sponsor
    @frequency = frequency
    @system_arguments = system_arguments
    @system_arguments[:tag] = :div
    @system_arguments[:test_selector] = "bulk-sponsorship-breadcrumbs"
    @system_arguments[:mb] ||= 2
  end

  private

  sig { returns Page }
  attr_reader :page

  sig { returns T.nilable(Symbol) }
  attr_reader :frequency

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled? && (@sponsor.present? || logged_in?)
  end

  sig { returns T::Boolean }
  def show_import_link?
    return false if page == Page::Import # we're already there!
    return false if page == Page::SelectFrequency # comes before the Import step
    true
  end

  sig { returns T::Boolean }
  def show_review_link?
    return false if page == Page::Review # we're already there!
    return false if page == Page::SelectFrequency # comes before the Review step
    return false if page == Page::Import # comes before the Review step
    true
  end

  sig { returns GitHubSponsors::Types::Sponsor }
  def sponsor
    @sponsor || current_user
  end

  sig { returns String }
  def get_started_path
    sponsors_bulk_sponsorship_frequencies_path(sponsor: sponsor)
  end

  sig { returns String }
  memoize def import_path
    new_sponsors_bulk_sponsorship_imports_path(sponsor: sponsor, frequency: frequency_param)
  end

  sig { returns String }
  def review_path
    edit_sponsors_bulk_sponsorship_imports_path(sponsor: sponsor, frequency: frequency_param)
  end

  sig { returns T.nilable(String) }
  memoize def frequency_param
    frequency == :recurring ? "recurring" : nil
  end
end
