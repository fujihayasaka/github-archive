# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorships::CheckoutSummaryComponent < ApplicationComponent
  extend T::Sig

  DEFAULT_HEADING_TAG = :h2
  SPONSORABLES_TO_DISPLAY = 10

  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      sponsorship_rows: T::Array[Sponsors::BulkSponsorshipRow],
      frequency: Symbol,
      heading_tag: Symbol,
      include_checkout_button: T::Boolean,
      system_arguments: T.untyped,
    ).void
  end
  def initialize(
    sponsor:,
    sponsorship_rows:,
    frequency:,
    heading_tag: DEFAULT_HEADING_TAG,
    include_checkout_button: false,
    **system_arguments
  )
    @sponsor = sponsor
    @sponsorship_rows = sponsorship_rows
    @frequency = frequency
    @heading_tag = heading_tag
    @include_checkout_button = include_checkout_button
    @system_arguments = system_arguments
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsor) }
  attr_reader :sponsor

  sig { returns(T::Array[Sponsors::BulkSponsorshipRow]) }
  attr_reader :sponsorship_rows

  sig { returns(Symbol) }
  attr_reader :frequency, :heading_tag

  sig { returns(Integer) }
  def sponsorship_count
    sponsorship_rows.size
  end

  sig { returns(String) }
  def frequency_text
    frequency == :one_time ? "one time" : "a month"
  end

  sig { returns(T::Boolean) }
  def truncate_sponsorables?
    sponsorship_count > SPONSORABLES_TO_DISPLAY
  end

  sig { params(rows: T::Array[Sponsors::BulkSponsorshipRow]).returns(String) }
  def sponsorables_sentence_for(rows)
    sponsorable_links = rows.map do |row|
      render(Sponsors::BulkSponsorshipImports::SponsorableLinkComponent.new(sponsorship_row: row))
    end

    to_sentence(
      sponsorable_links,
      words_connector: render(Primer::BaseComponent.new(tag: :span, color: :muted).with_content(", ")),
      last_word_connector: render(Primer::BaseComponent.new(tag: :span, color: :muted).with_content(", and ")),
      two_words_connector: render(Primer::BaseComponent.new(tag: :span, color: :muted).with_content(" and ")),
    )
  end

  sig { returns(T::Boolean) }
  def include_checkout_button?
    @include_checkout_button
  end

  sig { returns(T::Boolean) }
  def disable_checkout_button?
    sponsorship_rows.empty? || sponsor.has_commercial_interaction_restriction?
  end

  sig { returns(T::Boolean) }
  def include_sponsorables_list?
    !include_checkout_button?
  end

  sig { returns(String) }
  def total_amount
    sponsorship_rows.inject(Billing::Money.zero) { |sum, row| sum + row.amount }.format
  end
end
