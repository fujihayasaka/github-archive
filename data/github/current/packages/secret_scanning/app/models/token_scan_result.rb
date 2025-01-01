# typed: true
# frozen_string_literal: true

class TokenScanResult < ApplicationRecord::TokenScanningService # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend GitHub::SimplePagination

  include ActiveModel::Dirty

  belongs_to :repository
  belongs_to :resolver, class_name: "User"

  has_many :token_scan_result_locations, -> {
    order(created_at: :asc, id: :asc)
  }
  alias_method :locations, T.unsafe(:token_scan_result_locations)
  destroy_dependents_in_background :token_scan_result_locations

  has_many :included_locations, -> {
    where(ignore_token: :include).order(created_at: :asc, id: :asc)
  }, class_name: "TokenScanResultLocation"

  has_many :ignored_locations, -> {
    where(ignore_token: :exclude_by_path).order(created_at: :asc, id: :asc)
  }, class_name: "TokenScanResultLocation"

  enum :resolution, {
    revoked: 0,
    false_positive: 1,
    used_in_tests: 2,
    wont_fix: 3,
    reopened: 4,
    pattern_deleted: 5,
    pattern_edited: 6,
    resolution_unknown: 7,
    hidden_by_config: 8,
  }

  enum :scan_scope, {
    unknown: 0,
    repo: 1,
    commit: 2,
  }

  scope :resolved, -> { where.not(resolution: [nil, :reopened]) }
  scope :unresolved, -> { where(resolution: [nil, :reopened]) }
  scope :for_token_types, -> (token_types) { where(token_type: token_types) }

  scope :resolved_count, -> { joins(:included_locations).resolved.distinct.count }
  scope :unresolved_count, -> { joins(:included_locations).unresolved.distinct.count }

  scope :included, -> {
    joins(<<-SQL)
      INNER JOIN #{TokenScanResultLocation.table_name} first_location ON first_location.id = (
        SELECT MIN(id) FROM #{TokenScanResultLocation.table_name}
        WHERE token_scan_result_id = #{table_name}.id AND ignore_token = 0
      )
    SQL
  }

  scope :with_first_location, -> {
    first_location_columns = TokenScanResultLocation.column_names.map do |column|
      "first_location.#{column} as first_location_#{column}"
    end

    select("#{table_name}.*, #{first_location_columns.join(", ")}")
  }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }
  scope :most_recently_updated, -> { order(updated_at: :desc, id: :desc) }
  scope :least_recently_updated, -> { order(updated_at: :asc, id: :asc) }

  validates_presence_of :repository_id, :token_type
  validates_length_of :token_signature, is: 64
  validates_presence_of :resolver_id, :resolved_at, if: :resolution?

  before_create :set_number!
  after_create :mark_notify_subscribers
  after_commit :instrument_alert_updated_event, on: :update

  # Transient fields that are used to compute and return fields for API responses
  attr_accessor :raw_secret, :slug_type
  attr_accessor :publicly_leaked, :multi_repo

  def set_number!
    Sequence.create(self) unless Sequence.exists?(self)
    self.number = Sequence.next(self)
  end

  def sequence_type
    TokenScanResultSequence
  end

  # Find or create a token scan result for the given repository, token type,
  # and token signature.
  #
  # Returns the result that was either created or already existed.
  def self.create_from_found_token!(repo, token_type, token_signature, scan_scope = :unknown)
    attributes = { token_type: token_type, token_signature: token_signature }
    retry_on_find_or_create_error do
      repo.token_scan_results.find_by(attributes) || repo.token_scan_results.create!(attributes.merge({ scan_scope: scan_scope }))
    end
  end

  def first_location
    return @first_location if defined? @first_location

    @first_location = if attributes["first_location_id"].present?
      TokenScanResultLocation.find_by(id: attributes["first_location_id"].to_i)
    else
      included_locations.first
    end
  end

  def resolve!(resolution:, actor:, resolution_comment: nil)
    is_resolved = resolution != :reopened
    update!(resolution: resolution, resolver_id: actor.id, resolved_at: Time.zone.now, resolved: is_resolved, resolution_comment: resolution_comment)
    if resolution == :reopened
      GitHub.dogstats.increment("token_scanning_reopen_token")
    end
  end

  def resolved?
    resolution? && resolution != "reopened"
  end

  def reopened?
    resolution? && resolution == "reopened"
  end

  def notify_subscribers?
    @notify_subscribers == true && included_locations.exists?
  end

  # Returns true if the location was found in an archive file. For example, zip, xlsx, pptx, docx etc.
  # These locations have start and end line of location set to 0.
  def found_in_archive?
    first_location.present? && first_location.found_in_archive?
  end

  def instrument_alert_updated_event
    return unless saved_change_to_resolution?

    if resolved?
      GitHub.instrument "secret_scanning_alert.resolved", {
        alert_number: number,
        repository_id: repository_id,
        action: :resolved
      }
    elsif reopened?
      GitHub.instrument "secret_scanning_alert.reopened", {
        alert_number: number,
        repository_id: repository_id,
        action: :reopened
      }
    end
  end

  private

  def mark_notify_subscribers
    @notify_subscribers = true
  end
end
