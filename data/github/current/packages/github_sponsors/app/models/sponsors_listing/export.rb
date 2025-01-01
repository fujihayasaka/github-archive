# typed: true
# frozen_string_literal: true

class SponsorsListing::Export
  attr_reader :filter

  # filter - a Symbol or Array of Symbols to filter listings by state; choose from:
  #          :all - listings in any state will be included
  #          :draft
  #          :waitlisted
  #          :pending_approval
  #          :banned
  #          :approved
  #          :disabled
  def initialize(filter: :all)
    @filter = filter
  end

  def as_csv
    CSV.generate(encoding: Encoding::UTF_8) do |csv|
      # set the headers for the csv
      csv << %w[
        state
        login
        name
        email
        joined_at
      ]

      listings.each do |listing|
        user_id = listing.sponsorable_id
        email = listing.sponsorable.user? ? emails[user_id] : listing.sponsorable.billing_email

        csv << [
          listing.current_state_name,
          logins[user_id],
          names[user_id],
          email,
          listing.joined_at,
        ]
      end
    end
  end

  def filename
    "sponsors-waitlist-#{states.map(&:to_s).map(&:downcase).join("-")}-#{Date.current}.csv"
  end

  private

  def states
    @states ||= if filter.is_a?(Array)
      filter
    else
      [filter]
    end
  end

  def listings
    @listings ||= begin
      scope = SponsorsListing
      scope = scope.with_states(*states) unless filter == :all
      scope.includes(:sponsorable)
           .select(:state, :sponsorable_id, :contact_email_id, :joined_at)
           .oldest_join_date_first
    end
  end

  def user_ids
    @user_ids ||= listings.map(&:sponsorable_id)
  end

  def logins
    @logins ||= User.where(id: user_ids).pluck(:id, :login).to_h
  end

  def emails
    @emails ||= begin
      contact_email_ids = listings.map(&:contact_email_id)
      emails = UserEmail.where(id: contact_email_ids).pluck(:user_id, :email).to_h
    end
  end

  def names
    @names ||= Profile.where(user_id: user_ids).pluck(:user_id, :name).to_h
  end
end
