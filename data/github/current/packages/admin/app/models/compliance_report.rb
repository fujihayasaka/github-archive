# typed: true
# frozen_string_literal: true

class ComplianceReport < ApplicationRecord::Collab
  VALID_REPORT_TYPES = %w(download link group)
  MAX_SLUG_LENGTH = 100
  SLUG_REGEX = /\A[a-z0-9]+(-[a-z0-9]+)*\z/i
  SLUG_VALIDATION_MESSAGE = "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
  MAX_FILENAME_LENGTH = 250
  FILENAME_REGEX = /\A[a-z0-9\.\-_]+\z/i
  FILENAME_VALIDATION_MESSAGE = "may only contain alphanumeric characters, hyphens, underscores, and periods"
  MAX_URL_LENGTH = 250
  MAX_TITLE_LENGTH = 250
  MAX_DESCRIPTION_LENGTH = 125_000

  # Which accounts is the report available to?
  enum :availability, {
    ghec_accounts_only: 0,
    non_ghec_accounts_only: 1,
    all_accounts: 2,
  }, default: :ghec_accounts_only

  # Report file contents to be stored.
  attr_accessor :blob

  validates :slug,
    presence: true,
    length: { maximum: MAX_SLUG_LENGTH },
    uniqueness: true,
    format: { with: SLUG_REGEX, message: SLUG_VALIDATION_MESSAGE },
    if: :slug_changed?
  validates :report_type, presence: true, inclusion: { in: VALID_REPORT_TYPES }
  validates :filename,
    presence: true,
    if: :download?,
    format: { with: FILENAME_REGEX, message: FILENAME_VALIDATION_MESSAGE },
    length: { maximum: MAX_FILENAME_LENGTH }
  validates :url, presence: true, if: :link?, length: { maximum: MAX_URL_LENGTH }
  validate :ensure_url_is_valid, if: :url?
  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  validates :description, presence: true, length: { maximum: MAX_DESCRIPTION_LENGTH }
  attribute :description, StringFromBinary.new
  validates :display_order, numericality: { only_integer: true, allow_nil: true }

  after_save_commit :store_report
  after_destroy_commit :cleanup

  scope :published, -> { where(published: true) }
  scope :downloads, -> { where(report_type: "download") }
  scope :top_level_reports, -> { where(parent_id: nil).order(:display_order) }
  scope :for_ghec_account, -> { where(availability: [:all_accounts, :ghec_accounts_only]) }
  scope :for_non_ghec_account, -> { where(availability: [:all_accounts, :non_ghec_accounts_only]) }

  # Public: Get the human-readable value for a given availability enum value.
  #
  # availability - String representing the ComplianceReport#availability enum value.
  #
  # Example:
  #
  # > ComplianceReport.availability_for_humans("non_ghec_accounts_only")
  # => "Non-GHEC accounts only"
  #
  # Returns String.
  def self.availability_for_humans(availability)
    case availability.to_s
    when "ghec_accounts_only"
      "GHEC accounts only"
    when "non_ghec_accounts_only"
      "Non-GHEC accounts only"
    when "all_accounts"
      "All accounts"
    end
  end

  # Public: Is the report available to a given account?
  #
  # account - A Business or Organization.
  #
  # Returns Boolean.
  def available_to?(account)
    if account.is_a?(Business)
      return true if all_accounts? || ghec_accounts_only?
    elsif account.is_a?(Organization)
      return true if all_accounts?
      if account.business_plus?
        return true if ghec_accounts_only?
      else
        return true if non_ghec_accounts_only?
      end
    end

    false
  end

  def to_s
    slug
  end

  def to_param
    slug
  end

  def download?
    report_type == "download"
  end

  def link?
    report_type == "link"
  end

  def group?
    report_type == "group"
  end

  def child?
    parent_id.present?
  end

  def child_reports
    return ComplianceReport.none unless group?

    ComplianceReport.where(parent_id: id).order(:display_order)
  end

  def possible_parent_reports
    ComplianceReport.top_level_reports.where.not(id: id)
  end

  def storage
    GHECAdmin::Storage.make(filename_for_storage, :compliance_reports, :azure)
  end

  def content_type
    "application/pdf"
  end

  private

  def ensure_url_is_valid
    return unless url?

    errors.add(:url, "is not a valid http(s) URL") unless UrlHelper.valid_url?(url)
  end

  def filename_for_storage
    "#{GitHub.filename_prefix_for_env}/#{slug}-#{filename}"
  end

  def store_report
    return unless blob.present?
    storage.store(blob, content_type)
  end

  def cleanup
    storage.cleanup if download? && storage.exists?
  end
end
