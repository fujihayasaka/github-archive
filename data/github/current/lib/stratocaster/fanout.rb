# typed: true
# frozen_string_literal: true

module Stratocaster
  class Fanout
    # Public: Builds an instance of Stratocaster::Fanout.
    #
    # event - A Stratocaster::Event instance.
    # index - A Stratocaster::Indexer instance. See
    #         Stratocaster::Indexers::MysqlIndexer.
    #
    def initialize(event:, index:)
      @event = event
      @index = index
      @homepage_timeline_target_user_ids = nil
    end

    # Public: Builds and creates an index record for the Stratocaster::Event.
    #
    # Returns nothing.
    def perform
      return if @event.follow_event? && actor_is_spammy?

      timeline_types = Stratocaster::TimelineTypes::ELIGIBLE_FOR_FANOUT
      set_default_homepage_timeline_target_ids

      @index.with(@event) do
        index_entry_keys = timeline_types.map do |timeline_type|
          send("keys_for_#{timeline_type}")
        end.flatten.compact

        if index_entry_keys.any?
          log_payload = {
            "gh.stratocaster.event.id" => @event.id,
            "gh.stratocaster.event.type" => @event.event_type,
            "gh.stratocaster.event.action" => @event.action || Stratocaster::Event::NO_ACTION,
            "gh.stratocaster.event.sender_id" => @event.sender_id,
            "gh.stratocaster.event.actor_id" => @event.actor_id,
            "gh.stratocaster.event.repo_id" => @event.repo_id,
          }

          GitHub.logger.with_named_tags(log_payload) do
            start = Time.now
            @index.send(:insert, *index_entry_keys)
            elapsed_ms = (Time.now - start) * 1000

            log_index_entry_insertion_duration(elapsed_ms: elapsed_ms)
            log_index_entry_keys_count(index_entry_keys.size)
          end
        end
      end
    end

    private

    def actor_is_spammy?
      actor.present? && actor.spammy?
    end

    def actor
      @event.sender_record
    end

    def set_default_homepage_timeline_target_ids
      @homepage_timeline_target_user_ids = Stratocaster.
        attributes_class_for(@event.event_type).
        from_event(@event).
        targets

      if @homepage_timeline_target_user_ids.present?
        exclude_sender_from_homepage_timeline_targets!
      end
    end

    def exclude_sender_from_homepage_timeline_targets!
      @homepage_timeline_target_user_ids.reject! { |id| id == @event.sender_record.id }
    end

    def keys_for_public
      ["public"] if @event.public?
    end

    def keys_for_actor
      return [] if @event.sender.blank?
      keys = ["actor:#{@event.sender["id"]}"]
      keys.push(keys[0] + ":public") if @event.public?
      keys
    end

    def keys_for_repo
      return [] if @event.repo.blank?
      keys = ["repo:#{@event.repo["id"]}"]
      if @event.pull_request_or_issues_event?
        keys.push(keys[0] + ":issues")
      end
      keys
    end

    def keys_for_network
      return [] if @event.repo.blank? || !@event.public?
      ["network:#{@event.repo["source_id"]}:public"]
    end

    def keys_for_org
      return [] if @event.org.blank? || !@event.public?
      ["org:#{@event.org["id"]}:public"]
    end

    # Dispatches the current Event to the org all feed
    # which is an experimental timeline meant to replace 'org_members'.
    # Whereas 'org_members' stores a timeline per user per org,
    # 'org_all' stores one timeline per org and relies on filtering of
    # events on retrieval based on the viewing user's permissions on the
    # org and its repositories. 'org_all' has timeline keys of the format
    # "org:1111111".
    #
    # Returns an array of timeline keys.
    def keys_for_org_all
      return [] if @event.org.blank? || @event.watch_event?
      ["org:#{@event.org["id"]}"]
    end

    def keys_for_homepage_public
      return [] if !@event.public?
      targets = Array(@homepage_timeline_target_user_ids).uniq
      targets.map { |id| "user:#{id}:public" }
    end

    def keys_for_homepage_all
      return [] if @event.public?
      targets = Array(@homepage_timeline_target_user_ids).uniq
      targets.map { |id| "user:#{id}" }
    end

    def log_index_entry_insertion_duration(elapsed_ms:)
      GitHub.dogstats.distribution(
        "stratocaster.fanout.insert_index_entries",
        elapsed_ms,
        tags: dogstats_tags.all,
      )
    end

    def log_index_entry_keys_count(index_entry_keys_count)
      GitHub.dogstats.gauge(
        "stratocaster.fanout.index_entry_keys_count",
        index_entry_keys_count,
        tags: dogstats_tags.all,
      )
    end

    def dogstats_tags
      @dogstats_tags ||= Stratocaster::DogstatsTags.new(@event)
    end
  end
end
