# typed: strict
# frozen_string_literal: true

# Public: Represents terms and conditions that our users who participate in GitHub Sponsors can sign.
class SponsorsAgreement < ApplicationRecord::Domain::Sponsors
  extend GitHub::Encoding
  force_utf8_encoding :body

  include Instrumentation::Model

  AGREEMENT_NAMES_BY_KIND = T.let({
    optional_data_provision: "GitHub Maintainer Additional Terms for Optional Data Provision",
    invoiced_sponsor: "GitHub Invoiced Sponsor Agreement",
  }.freeze, T::Hash[Symbol, String])

  enum :kind, {
    # Deprecated. Was an extra set of terms that maintainers could agree to in order to receive sponsorships that
    # the sponsor paid for via invoice. See https://github.com/github/sponsors/issues/2512.
    optional_data_provision: 0,

    # Refers to terms signed on behalf of an organization so that it can become an invoiced sponsor
    # and pay for its sponsorships via invoiced billing. See https://github.com/github/sponsors/issues/4863.
    invoiced_sponsor: 1,
  }, suffix: true

  before_validation :set_organization_from_login, if: :organization_login

  validates :body, :version, :kind, presence: true
  validates :version, uniqueness: { scope: :kind, case_sensitive: false }
  validate :version_is_later_than_previous
  validate :organization_exists_if_specified, on: :create

  sig { params(organization_login: T.nilable(String)).returns(T.nilable(String)) }
  attr_writer :organization_login

  has_many :invoiced_signatures, class_name: "SponsorsInvoicedAgreementSignature", inverse_of: :agreement
  belongs_to :organization

  scope :newest_first, -> { order(version: :desc) }
  scope :for_kind, ->(kind) { where(kind: kind) }
  scope :with_version, ->(version) { where(version: version) }
  scope :not_org_specific, -> { where(organization_id: nil) }
  scope :for_org, ->(org) { where(organization_id: org) }

  scope :with_latest_version, -> do
    outer_agreements = arel_table
    inner_agreements = arel_table.alias("spon_agr")
    # WHERE sponsors_agreements.version = (
    #   SELECT MAX(version)
    #   FROM sponsors_agreements AS spon_agr
    #   WHERE spon_agr.kind = sponsors_agreements.kind
    # )
    latest_version_for_kind = outer_agreements
      .project(inner_agreements[:version].maximum)
      .from(inner_agreements)
      .where(inner_agreements[:kind].eq(outer_agreements[:kind]))
    where(outer_agreements[:version].eq(latest_version_for_kind))
  end

  # Public: Get the most recent non-org-specific version of the Invoiced Sponsor agreement.
  #
  # This is the one that is "current" in terms of collecting new signatures.
  sig { returns(T.nilable(SponsorsAgreement)) }
  def self.current_invoiced_sponsor_agreement
    invoiced_sponsor_kind.not_org_specific.newest_first.first
  end

  sig { returns(T::Hash[String, T::Hash[T.nilable(Integer), String]]) }
  def self.latest_version_by_kind_and_organization_id
    rows = select("kind, organization_id, MAX(version) AS latest_version")
      .group(:kind, :organization_id)
    rows.each_with_object({}) do |agreement, hash|
      hash[agreement.kind] ||= {}
      hash[agreement.kind][agreement.organization_id] = T.unsafe(agreement).latest_version
    end
  end

  # Public: Get a count of how many signatures are not expired for the agreement.
  #
  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of SponsorsAgreement records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(agreements, :total_active_signatures)
  #
  #   agreements.each do |agreement|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     agreement.total_active_signatures
  #   end
  #
  # Returns an Integer.
  batch_method :total_active_signatures do |agreements|
    invoiced_sponsor_agreements = agreements.select(&:invoiced_sponsor_kind?)
    invoiced_signature_counts = SponsorsInvoicedAgreementSignature.not_expired
      .for_agreement(invoiced_sponsor_agreements).group(:sponsors_agreement_id).count
    agreements.each_with_object({}) do |agreement, hash|
      hash[agreement] = if agreement.invoiced_sponsor_kind?
        invoiced_signature_counts[agreement.id] || 0
      else
        0
      end
    end
  end

  # Public: Returns a human-readable string describing this agreement, based on the kind.
  sig { returns(String) }
  def name
    T.must(AGREEMENT_NAMES_BY_KIND[kind.to_sym])
  end

  sig { returns(String) }
  def pdf_filename
    "#{name}-#{Date.current}.pdf"
  end

  # Public: The agreement's content as HTML.
  sig { returns(String) }
  def body_html
    return GitHub::HTMLSafeString::EMPTY if body.blank?
    GitHub::Goomba::MarkdownPipeline.to_html(body)
  end

  sig { returns(Symbol) }
  def event_prefix
    :sponsors_agreement
  end

  sig { params(prefix: T.any(String, Symbol)).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      event_prefix => self,
      :version => version,
      :kind => kind,
    }
  end

  # Public: Get a representation of this agreement's kind that's suitable for use in the Hydro
  # `github.sponsors.v1.entities.SponsorsAgreement.Kind` enum.
  sig { returns(String) }
  def hydro_kind
    # See lib/hydro/schemas/github/sponsors/v1/entities/sponsors_agreement_pb.rb
    if invoiced_sponsor_kind?
      "INVOICED_SPONSOR"
    elsif optional_data_provision_kind?
      "OPTIONAL_DATA_PROVISION"
    else
      "UNKNOWN"
    end
  end

  sig { returns(String) }
  def to_s
    "#{name}, version #{version}"
  end

  sig { returns T.nilable(String) }
  def organization_login
    return @organization_login if @organization_login
    return unless organization_id
    @organization_login = organization&.display_login
  end

  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@organization_login) if defined?(@organization_login)
  end

  private

  sig { void }
  def version_is_later_than_previous
    previous_agreements = self.class.where(kind: kind).newest_first
    previous_agreements = if organization_id
      previous_agreements.for_org(organization_id)
    else
      previous_agreements.not_org_specific
    end
    previous_agreement = previous_agreements.first
    return unless previous_agreement

    if version <= previous_agreement.version
      org = organization
      org_note = if org
        "@#{org.display_login}-specific "
      end
      errors.add(:version, "#{version} must come after the previous #{org_note}#{kind} version, " \
        "#{previous_agreement.version}")
    end
  end

  sig { void }
  def set_organization_from_login
    return if organization_login.blank?
    self.organization = Organization.find_by_login(organization_login)
  end

  sig { void }
  def organization_exists_if_specified
    return if organization_login.blank? && organization_id.nil?

    unless organization
      if organization_login.present?
        errors.add(:organization_login, "does not match an existing organization")
      else
        errors.add(:organization_id, "does not exist")
      end
    end
  end
end
