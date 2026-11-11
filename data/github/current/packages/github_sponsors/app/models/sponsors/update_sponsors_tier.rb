# typed: true
# frozen_string_literal: true

module Sponsors

  # Public: A Plain Old Ruby Object (PORO) used for updating an existing Sponsors tier.
  class UpdateSponsorsTier
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to update a sponsors tier
    # inputs[:tier] - The sponsors tier to update.
    # inputs[:description] - A short description of the sponsorship tier.
    # inputs[:amount] - How much this sponsorship tier should cost per month in USD.
    # inputs[:viewer] - Current viewer from GraphQL context.
    # inputs[:welcome_message] - An optional welcome message for new sponsors of this tier.
    # inputs[:repository_id] - An optional Repository ID to associate with the tier, to indicate all sponsors who use
    #                          this tier should be granted access to the repository.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(tier:, description:, amount:, viewer:, welcome_message: nil,
                   repository_id: nil, require_repository: false)
      @tier = tier
      @description = description
      @amount = amount
      @viewer = viewer
      @welcome_message = welcome_message&.strip
      @repository_id = repository_id
      @require_repository = require_repository

      if changing_repository?
        @old_sponsorship_repositories = @tier.sponsorship_repositories.to_a
      end
    end

    def call
      updated_tier = update_tier

      tier.instrument_repository_change(actor: viewer)
      tier.instrument_description_change(actor: viewer)
      tier.instrument_welcome_message_change(actor: viewer)

      revoke_old_repository_access if changing_repository?

      invite_eligible_sponsors_to_repo if adding_repository?

      updated_tier
    end

    private

    attr_reader :tier, :amount, :description, :repository_id, :old_sponsorship_repositories, :viewer,
      :welcome_message, :require_repository

    delegate :sponsorable, to: :tier

    def monthly_price_in_cents
      @monthly_price_in_cents ||= amount * 100
    end

    def yearly_price_in_cents
      if tier.one_time?
        monthly_price_in_cents
      else
        monthly_price_in_cents * 12
      end
    end

    def adding_repository?
      repository_id.present? && tier.repository_id_previously_changed?
    end

    def changing_repository?
      return @changing_repository if defined?(@changing_repository)
      @changing_repository = repository_id.to_s != tier.repository_id.to_s
    end

    def update_tier
      unless tier.editable_by?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to change the Sponsors tier.")
      end

      tier.description = description || ""
      tier.monthly_price_in_cents = monthly_price_in_cents
      tier.yearly_price_in_cents = yearly_price_in_cents
      tier.name = tier.generate_name
      tier.welcome_message = welcome_message
      tier.require_repository = require_repository
      tier.repository_id = repository_id

      if tier.save
        tier
      else
        errors = tier.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not update Sponsors tier: #{errors}")
      end
    end

    def invite_eligible_sponsors_to_repo
      tier.active_sponsorships.find_each(&:enqueue_grant_repository_access_job)
    end

    def revoke_old_repository_access
      old_sponsorship_repositories.each(&:enqueue_revoke_access_job)
    end
  end
end
