# typed: true
# frozen_string_literal: true

class ScienceEvent < ApplicationRecord::Collab
  extend GitHub::Encoding
  include GitHub::Validations
  include GitHub::Memoizer
  force_utf8_encoding :payload

  MISMATCH = "mismatch".freeze
  SAMPLE = "sample".freeze

  ACCEPTABLE_DELAY = 1.5
  CLUSTER_NAME = :collab

  DELETE_BATCH_SIZE = 10

  validates :name, unicode3: true

  # Public: the number of mismatches to retrieve by default in the UI or console.
  MISMATCH_DISPLAY_LIMIT = 5

  # Public: the number of mismatches to store in MySQL
  MISMATCH_CAP = 10_000

  # Public: the number of samples to retrieve by default in the UI or console.
  SAMPLE_DISPLAY_LIMIT = 20

  # Public: the number of samples to store in MySQL
  SAMPLE_CAP = 10_000

  ERROR_MESSAGE = <<~ERROR_MESSAGE

      It looks like you're trying to serialize potentially private information.

      When setting up the the payload for your experiment, please make sure that what you return
      from the experiment is safe to serialize. You can specify which fields to compare by using
      `to_json(only: [:key1, :key2])` from your experiment block or use `e.compare { true }` if
      you just want the performance measurements and not the mismatches.

      Happy experimenting! ✨

      Original error message:
  ERROR_MESSAGE

  scope :samples, -> (name) { where(name: name, event_type: SAMPLE) }
  scope :mismatches, -> (name) { where(name: name, event_type: MISMATCH) }

  memoize def parsed_payload
    ActiveSupport::JSON.decode(payload)
  rescue Yajl::ParseError
    nil
  end

  def parsed_payload?
    !parsed_payload.nil?
  end

  def self.clear(name)
    # just delete them all, no need for callbacks
    where(name: name).in_batches(of: DELETE_BATCH_SIZE) do |relation|
      throttle do
        relation.delete_all
      end
    end

    true
  end

  def self.push_mismatch(name, payload)
    unless can_push_data?
      GitHub.dogstats.increment("science_events.push_throttled", tags: ["event_type:mismatch", "name:#{name}"])
      return
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      create(name: name, event_type: MISMATCH, payload: payload)
    end
    GitHub.dogstats.increment("science_events.push", tags: ["event_type:mismatch", "name:#{name}"])
  end

  def self.push_sample(name, payload)
    unless can_push_data?
      GitHub.dogstats.increment("science_events.push_throttled", tags: ["event_type:sample", "name:#{name}"])
      return
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      create(name: name, event_type: SAMPLE, payload: payload)
    end
    GitHub.dogstats.increment("science_events.push", tags: ["event_type:sample", "name:#{name}"])
  end

  def self.mismatch_count(name)
    ActiveRecord::Base.connected_to(role: :reading) do
      mismatches(name).count
    end
  end

  def self.sample_count(name)
    ActiveRecord::Base.connected_to(role: :reading) do
      samples(name).count
    end
  end

  def self.mismatch_page(page: 1, name:)
    ActiveRecord::Base.connected_to(role: :reading) do
      page(mismatches(name), MISMATCH_DISPLAY_LIMIT, page)
    end
  end

  def self.sample_page(page: 1, name:)
    ActiveRecord::Base.connected_to(role: :reading) do
      page(samples(name), SAMPLE_DISPLAY_LIMIT, page)
    end
  end

  def self.all_names
    distinct.pluck(:name)
  end

  def self.trim_all
    all_names.each do |name|
      trim_mismatches(name)
      trim_samples(name)
    end
  end

  def self.trim_mismatches(name)
    trim(mismatches(name), MISMATCH_CAP, name, "mismatch")
  end

  def self.trim_samples(name)
    trim(samples(name), SAMPLE_CAP, name, "sample")
  end

  def self.page(ascope, limit, page)
    # in order to remove the warnings from vivid cortex this has been optimized
    # First we select the ids based on the [name, event_type]
    # Then we select the rows based on those ids

    offset = limit * ((page = page.to_i - 1) < 0 ? 0 : page)
    # calculate ids first using the name, event_type index
    ids = ascope.
      limit(limit).
      offset(offset).
      order("id DESC").
      pluck(:id)

    max_id = ids.first
    min_id = ids.last

    # Then grab the payloads based on id
    ascope.where("id BETWEEN ? AND ?", min_id, max_id).order("id DESC")
  end

  def self.trim(ascope, cap, name, event_type)
    newest = ascope.limit(cap).order("id DESC").pluck(:id)
    ascope.where("id NOT IN (?)", newest).in_batches(of: DELETE_BATCH_SIZE) do |relation|

      GitHub.dogstats.count("science_events.trim", relation.size, tags: ["name:#{name}", "event_type:#{event_type}"])

      throttle do
        with_write do
          relation.delete_all
        end
      end
    end
  end

  def self.can_push_data?
    delay = Freno.client.replication_delay(store_name: CLUSTER_NAME)

    delay < ACCEPTABLE_DELAY
  rescue Freno::Error
    false
  end

  private_class_method :page
  private_class_method :trim
end
