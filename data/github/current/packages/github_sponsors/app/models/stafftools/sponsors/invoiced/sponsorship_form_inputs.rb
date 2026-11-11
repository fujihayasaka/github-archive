# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class SponsorshipFormInputs
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :sponsorship_id, :integer
        attribute :sponsorable_login, :string
        attribute :amount_in_dollars, :integer
        attribute :is_recurring, :boolean, default: true
        alias :recurring? :is_recurring
        attribute :end_month, :integer
        attribute :end_year, :integer
        attribute :is_public, :boolean, default: true
        alias :public? :is_public
        attribute :email_opt_in, :boolean, default: false
        alias :opted_in_to_email? :email_opt_in
        attribute :active_on, :date
        attribute :skip_proration, :boolean, default: :false

        validates :sponsors_listing, :amount_in_dollars, presence: true

        def self.from_sponsorship(sponsorship)
          return unless sponsorship
          self.new(
            sponsorship_id: sponsorship.id,
            sponsorable_login: sponsorship.sponsorable,
            amount_in_dollars: sponsorship.monthly_price_in_dollars.to_i,
            end_month: sponsorship.expires_at&.month,
            end_year: sponsorship.expires_at&.year,
            is_recurring: sponsorship.recurring_payment?,
            is_public: sponsorship.privacy_public?,
            email_opt_in: sponsorship.is_sponsor_opted_in_to_email?,
            active_on: sponsorship.pending_activation_date,
            skip_proration: sponsorship.skip_proration,
          )
        end

        def sponsorable
          return @sponsorable if defined?(@sponsorable)
          @sponsorable = ::User.find_by_login(sponsorable_login)
        end

        def sponsors_listing
          return @sponsors_listing if defined?(@sponsors_listing)
          @sponsors_listing = sponsorable&.sponsors_listing
        end

        def end_date
          return unless recurring?
          month = end_month
          return unless month

          year = end_year
          return unless year
          Date.new(year, month, 1).end_of_month if year.positive? && month.positive?
        end

        def parent_tier_id
          return @parent_tier_id if defined?(@parent_tier_id)
          @parent_tier_id = SponsorsTier.closest_lesser_value_tier_for(sponsors_listing,
            amount: amount_in_dollars,
            is_recurring: recurring?
          )&.id
        end
      end
    end
  end
end
