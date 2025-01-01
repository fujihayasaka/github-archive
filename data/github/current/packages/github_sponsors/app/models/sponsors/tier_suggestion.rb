# typed: true
# frozen_string_literal: true

class Sponsors::TierSuggestion
  INSPIRING_USER_DISPLAY_COUNT = 12

  def self.inspiring_users
    User.where(login: Data.inspiring_users.sample(INSPIRING_USER_DISPLAY_COUNT))
  end

  def self.all
    Data.categorized.each_with_object([]) do |group, acc|
      acc.concat(group[:tiers].map { |tier_data| new(category: group[:category], tier_data: tier_data) })
    end
  end

  def self.categories
    self.all.map(&:category).uniq
  end

  # Public: Returns an Array of Sponsors::TierSuggestion instances with a given frequency
  #
  # frequency - The tier suggestion frequency (i.e. :recurring or :one_time).
  #
  # Returns an Array of Sponsors::TierSuggestion instances.
  def self.for_frequency(frequency)
    self.all.select { |tier_suggestion| tier_suggestion.frequency == frequency.to_sym }
  end

  # Public: Returns an Array of Sponsors::TierSuggestion instances for a given category
  #
  # category - The tier suggestion category.
  #
  # Returns an Array of Sponsors::TierSuggestion instances.
  def self.for_category(category)
    self.all.select { |tier_suggestion| tier_suggestion.category == category }
  end

  def self.emoji_alias(category:)
    Data.categorized.find { |el| el[:category] == category }[:emoji_alias]
  end

  delegate :description, :description_html, :generate_name, :monthly_price_in_cents, :recurring?, to: :record

  attr_reader :category, :record

  def initialize(category:, tier_data:)
    @category = category
    @tier_data = tier_data
    @record = build_record(tier_data)
  end

  alias name generate_name

  def frequency
    record.frequency.to_sym
  end

  def tier_id
    @tier_id ||= "tier-suggestion-#{generate_name.parameterize}"
  end

  def input_id
    unique_suffix = Digest::MD5.hexdigest(description).slice(...8) # rubocop:todo GitHub/InsecureHashAlgorithm
    @input_id ||= "#{tier_id}-#{unique_suffix}"
  end

  def preview_tier_id
    "preview-#{tier_id}"
  end

  def preview_reward_id
    "preview-#{input_id}"
  end

  # Public: Get the dollar value of the tier suggestion in USD.
  #
  # Returns an Integer, e.g., 1 for a $1 tier.
  def amount
    record.monthly_price_in_dollars.to_i
  end

  def preselect?
    @tier_data[:preselect].present?
  end

  alias preselect preselect?

  private

  def build_record(tier_data)
    SponsorsTier.new(
      frequency: tier_data[:frequency],
      monthly_price_in_cents: tier_data[:monthly_price_in_cents],
      description: tier_data[:description]
    )
  end

  class Data
    def self.inspiring_users
      if Rails.env.development?
        %w( draft-user waitlisted-user approved-user draft-org waitlisted-org approved-org missingno )
      else
        %w( alexellis calebporzio dlemstra erikaheidi funkypenguin jina johnleider julialang lando lpil
            mariatta matkoch nzakas posva slurps-mad-rips stancl tannerlinsley tchiotludo valadas )
      end
    end

    def self.categorized
      [
        {
          category: :recognition,
          emoji_alias: :tada,
          tiers: [
            {
              preselect: true,
              frequency: :recurring,
              monthly_price_in_cents: 5_00,
              description: "- Get a Sponsor badge on your profile"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 25_00,
              description: "- Logo or name goes in my project README"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 100_00,
              description: "- Logo or name on project website"
            },
            {
              preselect: true,
              frequency: :one_time,
              monthly_price_in_cents: 10_00,
              description: "- Get a shoutout on Twitter"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 50_00,
              description: "- Earn a mention in our Release notes"
            },
          ],
        },
        {
          category: :access_to_code,
          emoji_alias: :robot,
          tiers: [
            {
              frequency: :recurring,
              monthly_price_in_cents: 25_00,
              description: "- Access to private repositories"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 100_00,
              description: "- Access to pre-release builds of my project"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 500_00,
              description: "- Get a company license for my project"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 50_00,
              description: "- Get access to my sponsorware repository "
            },
          ],
        },
        {
          category: :community_and_education,
          emoji_alias: :notebook,
          tiers: [
            {
              frequency: :recurring,
              monthly_price_in_cents: 10_00,
              description: "- You'll receive my weekly newsletter updates"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 25_00,
              description: "- Join my community chat space"
            },
            {
              frequency: :recurring,
              monthly_price_in_cents: 30_00,
              description: "- Access to my videos, screencasts, and tutorials"
            },
          ],
        },
        {
          category: :facetime_and_consulting,
          emoji_alias: :slightly_smiling_face,
          tiers: [
            {
              frequency: :recurring,
              monthly_price_in_cents: 1000_00,
              description: "- I'll join your company chat app for help and support"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 200_00,
              description: "- One hour pair-programming session"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 350_00,
              description: "- One hour consulting or mentorship"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 500_00,
              description: "- I'll run a workshop for your team"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 2000_00,
              description: "- I'll give a talk at your conference"
            },
          ],
        },
        {
          category: :project_work,
          emoji_alias: :hammer_and_wrench,
          tiers: [
            {
              frequency: :recurring,
              monthly_price_in_cents: 100_00,
              description: "- Have your bug reports prioritized"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 1000_00,
              description: "- One bug or medium sized bounty"
            },
            {
              frequency: :one_time,
              monthly_price_in_cents: 5000_00,
              description: "- Large contract project – contact me!"
            },
          ],
        },
      ]
    end
  end
end
