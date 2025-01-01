# typed: true
# frozen_string_literal: true

class SendSponsorsPreviewEmailJob < ApplicationJob
  class InvalidRepository < StandardError; end

  queue_as :sponsors_emails

  retry_on_dirty_exit

  def perform(actor:, sponsors_listing:, frequency:, welcome_message:, repository_id:)
    preview_tier = SponsorsTier.new(
      frequency: frequency,
      sponsors_listing: sponsors_listing,
      welcome_message: welcome_message,
      repository_id: repository_id
    )
    ensure_repository_is_valid(preview_tier)

    SponsorsPrimerMailer.now_sponsoring(
      sponsorable: sponsors_listing.sponsorable,
      sponsor: actor,
      sponsorship_amount: "$XX",
      tier: preview_tier,
      sponsor_next_billing_date: Time.now,
    ).deliver_now
  end

  private

  # Ensure sponsorable has access to this repository and is valid (private, org
  # owned). Otherwise, someone can pass any repository_id to this job and find
  # out the name of repos they do not own by sending test emails with random
  # repository_ids from the sponsors tier form.
  def ensure_repository_is_valid(tier)
    repository_errors = tier.sponsors_only_repository_errors

    if repository_errors.any?
      raise InvalidRepository.new(repository_errors.to_sentence)
    end
  end
end
