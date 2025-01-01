# typed: true
# frozen_string_literal: true

class SponsorsCriterion < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  self.table_name = "sponsors_criteria"

  enum :criterion_type, [:checkbox, :text]
  enum :applicable_to, {
    all: 0,
    user: 1,
    organization: 2,
    using_supported_fiscal_host: 3,
  }, prefix: true

  # Slugs should be be underscored and without spaces, and not begin or end
  # with an underscore, e.g. `account_age`
  SLUG_REGEXP = /\A[a-z0-9]+(_[a-z0-9]+)*\z/i

  validates :slug,
    presence: true,
    format: { with: SLUG_REGEXP },
    length: { minimum: 3, maximum: 60 }
  validates(:slug,
    uniqueness: { case_sensitive: false },
    if: -> { T.bind(self, SponsorsCriterion); errors[:slug].blank? }
  )
  validates :description, presence: true

  has_many :sponsors_memberships_criteria,
    class_name: "SponsorsMembershipsCriterion",
    dependent: :destroy

  scope :active, -> { where(active: true) }
  scope :manual, -> { active.where(automated: false) }
  scope :applicable_to, ->(val) { where(applicable_to: val) }

  # Public: Returns the criteria records that are applicable to a sponsorable.
  #
  # sponsorable - The User or Organization to get criteria for.
  sig do
    params(
      sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable)
    ).returns(ActiveRecord::Relation)
  end
  def self.for(sponsorable)
    return self.none unless sponsorable.present?
    applicable = [:all]

    if sponsorable.organization?
      applicable << :organization
    else
      applicable << :user
    end

    if sponsorable.uses_sponsors_fiscal_host?
      applicable << :using_supported_fiscal_host
    end

    active.applicable_to(applicable)
  end

  # Public: The context for audit log events involving a SponsorsCriterion.
  sig { params(prefix: T.any(String, Symbol)).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    {
      prefix.to_sym => slug,
      "#{prefix}_id".to_sym => id,
    }
  end
end
