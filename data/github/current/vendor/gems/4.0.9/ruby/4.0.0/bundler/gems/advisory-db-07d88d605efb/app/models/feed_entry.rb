# frozen_string_literal: true

require "github/encoding"
require "normal_yaml"

class FeedEntry < ApplicationRecord
  belongs_to :advisory_review, optional: true

  attr_readonly :identifier

  FEED_ENTRY_ECOSYSTEMS = {
    "rubysec" => "rubygems",
    "friends_of_php" => "composer",
    "npm" => "npm",
    "rustsec" => "rust",
    "pypa_advisory" => "pip",
    "go" => "go",
  }.freeze

  enum :source, AdvisoryDB.sources
  enum :resolution_state, { unresolved: 0, resolving: 1, resolved: 2 }
  enum :ml_reject_prediction, { unknown: 0, reject: 1, not_reject: 2 }, prefix: "ml"

  serialize :raw_payload, coder: NormalYAML
  serialize :advisory_payload, coder: NormalYAML

  validates :source, presence: true
  validates :identifier, presence: true, uniqueness: { case_sensitive: true }, on: :create
  validates :cve_id, cve_id: true
  validates :raw_payload, presence: true
  validates :advisory_payload, presence: true

  extend ::GitHub::Encoding
  force_utf8_encoding :raw_payload,
    :advisory_payload

  after_create do
    AdvisoryDB.stats.increment(
      "feed_entry.create",
      tags: AdvisoryDB.dogtags(source: source),
    )
  end

  after_update do
    AdvisoryDB.stats.increment(
      "feed_entry.update",
      tags: AdvisoryDB.dogtags(source: source),
    )
  end

  def self.import(identifier:, **attributes)
    find_or_initialize_by(identifier: identifier).tap do |feed_entry|
      feed_entry.attributes = attributes
      feed_entry.save!
    end
  end

  def self.mark_as_resolving(feed_entry_id)
    transaction do
      lock.find_by(resolution_state: "unresolved", id: feed_entry_id).tap do |feed_entry|
        feed_entry&.update!(resolution_state: "resolving")
      end
    end
  end

  def to_param
    identifier
  end

  def mark_as_unresolved
    return if unresolved?

    update!(resolution_state: "unresolved")
  end

  def mark_as_resolved
    update!(resolution_state: "resolved")
  end

  def previous_changes_significant?
    cve_id_previously_changed? || advisory_payload_previously_changed?
  end

  def unresolved_changes
    changed_from_values = {}
    changed_to_values = {}

    # figure out what the original values were changed from since the last resolution
    versions.reverse_each do |version|
      break if version.changeset["resolution_state"].present? && version.changeset["resolution_state"][1] == "resolved"

      if version.changeset["cve_id"].present?
        changed_from_values["cve_id"] = version.changeset["cve_id"][0]
      end

      if version.changeset["advisory_payload"].present?
        changed_from_values["advisory_payload"] = version.changeset["advisory_payload"][0]
      end
    end

    # cve_id is unresolved if current one doesn't match the last one we had at resolution
    # and it doesn't match an existing advisory review value
    if changed_from_values.key?("cve_id") && changed_from_values["cve_id"] != cve_id && (
      !advisory_review || advisory_review.cve_id != cve_id
    )
      changed_to_values["cve_id"] = cve_id
    end

    # figure out which advisory_payload attributes are unresolved
    if changed_from_values.key?("advisory_payload")
      if advisory_review
        normalized_feed_payload = AdvisoryPayload.new(data: advisory_payload).data
        normalized_advisory_review_payload = AdvisoryPayload.new(data: advisory_review.advisory_payload).data
      end

      payload_changes = {}

      collection_attributes = ["cwe_ids", "references"]
      advisory_payload.each do |attribute, current_value|
        previous_value = changed_from_values["advisory_payload"].present? ? changed_from_values["advisory_payload"][attribute] : nil
        # current advisory payload attribute doesn't match the last one we had at resolution
        next unless previous_value != current_value && (
          # and it doesn't match an existing advisory review value
          !advisory_review || normalized_advisory_review_payload[attribute] != normalized_feed_payload[attribute]
        )

        # for payload values that are collections, we need to diff the previous and current values to get what changed within the collection
        # includes minus-prefixed values to represent a change of removal
        if collection_attributes.include?(attribute) && previous_value.present?
          added_members = current_value - previous_value
          removed_members = previous_value - current_value
          payload_changes[attribute] = added_members + removed_members.map { |member| "-#{member}" }
        else
          payload_changes[attribute] = current_value
        end
      end

      changed_to_values["advisory_payload"] = payload_changes if payload_changes.present?
    end

    changed_to_values
  end

  def subject_to_blocklist?
    AdvisoryDB.source_subject_to_blocklist?(source)
  end

  # Skip import of feed entries that are already in the process of being
  # resolved by a ResolveFeedEntryJob or the last resolution failed and its
  # stuck in the resolving state.
  def skip_import?
    resolving?
  end

  def hydro_payload
    {
      source: hydro_source,
      identifier: identifier,
      cve_id: cve_id || "",
      white_source_id: white_source_id || "",
      advisory_payload: AdvisoryPayload.new(data: advisory_payload).hydro_payload,
      created_at: created_at,
      updated_at: updated_at,
      ghsa_id: advisory_review&.ghsa_id || "",
    }
  end

  def hydro_source
    source.upcase
  end

  def ecosystem
    FEED_ENTRY_ECOSYSTEMS[source]
  end

  def cna
    # API 2.0 payload || API 1.0 payload
    raw_payload["sourceIdentifier"] || raw_payload.dig("cve", "CVE_data_meta", "ASSIGNER")
  end

  def cpe_match_criteria
    # API 1.0 payloads have a `CVE_data_version` key
    if raw_payload["CVE_data_version"]
      raw_payload.dig("configurations", "nodes")&.each_with_object([]) do |node, criteria|
        node["cpe_match"]&.each do |cpe_match|
          criteria << cpe_match["cpe23Uri"]
        end
      end
    else # The payload is from API 2.0
      raw_payload["configurations"]&.each_with_object([]) do |nodes, criteria|
        nodes["nodes"].each do |node|
          node["cpeMatch"].each do |cpe_match|
            criteria << cpe_match["criteria"]
          end
        end
      end
    end
  end

  def withdrawn?
    advisory_payload[:withdrawn]
  end
end
