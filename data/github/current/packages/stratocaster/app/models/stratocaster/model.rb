# typed: false
# frozen_string_literal: true

module Stratocaster
  class Model < ApplicationRecord::Stratocaster
    self.table_name = "stratocaster_events"
    cattr_reader :coder, default: Coders.compose(
      MessagePack, Coders::Gzip.new,
      default: {},
      errors: [MessagePack::UnpackError, Zlib::Error]
    ) { |e, _value|
      GitHub.dogstats.increment "stratocaster.bad_gzip"

      msg = "Error deserializing stratocaster event"
      # rubocop:disable Style/HashSyntax
      GitHub.logger.error(
        msg,
        exception: e,
        "gh.stratocaster.adapter_name" => name,
      )
      Failbot.report(e, type: msg)
    }

    store :raw_data,
      accessors: %i[created_at event_type org payload repo sender states team_members url user],
      coder: coder

    before_create :set_created_at # `updated_at` is set by rails at this point

    def self.create_from_event!(event)
      create! event.model_attributes
    end

    def self.from_event(event)
      new event.model_attributes
    end

    def self.get(key)
      events_for(key).first
    end

    # Array of Stratocaster::Events, in the order the keys are provided
    def self.get_all(*keys)
      models = events_for(keys).index_by(&:id)
      keys.map { |k| models[k] }
    end

    def self.events_for(ids)
      where(id: ids).filter(&:valid_event?).map(&:to_event)
    end

    def update_from_event!(event)
      update! event.model_attributes
    end

    def to_event
      Stratocaster::Event.new \
        raw_data.
          except(:targets).
          merge(id: id, updated_at: updated_at)
    end

    def valid_event?
      raw_data.present?
    end

    def created_at
      Time.zone.at super if super
    end

    private

    def set_created_at
      # We have to force created_at to a timestamp using .to_i.
      # See https://github.com/github/github/issues/122520
      self.created_at ||= updated_at.to_i
    end
  end
end
