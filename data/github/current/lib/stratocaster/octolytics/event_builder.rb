# typed: true
# frozen_string_literal: true

module Stratocaster
  module Octolytics
    class EventBuilder
      def initialize(strat_event)
        @strat_event = strat_event
      end

      # For the given Stratocaster::Event, return one or more dictionaries of
      # :measures, :dimensions, and :context keys suitable for sending as the
      # payload of an Octolytics event.
      def events
        payloads.map do |payload|
          {
            event_type: "stratocaster_#{@strat_event.kind}",
            dimensions: dimensions,
            measures: {},
            context: payload,
            timestamp: @strat_event.created_at.to_i,
          }
        end
      end

      private

      # Return dimensions to add to the event(s) sent to octolytics as a dictionary of
      # Strings to Strings.
      def dimensions
        return @dimensions if defined?(@dimensions)

        @dimensions = [
          Attributes.flatten(hash: @strat_event.user, prefix: "user"),
          Attributes.flatten(hash: @strat_event.repo, prefix: "repo"),
          Attributes.flatten(hash: @strat_event.org, prefix: "org"),
          Attributes.flatten(hash: @strat_event.sender, prefix: "sender"),
        ].each_with_object({}) { |d, dimensions| dimensions.merge!(d) }

        @dimensions["stratocaster_id"] = @strat_event.id
        @dimensions["actor_id"] = @dimensions["sender_id"]
        @dimensions["public"] = @strat_event.public

        @dimensions.reject! { |_k, v| v.nil? }
        @dimensions
      end

      # Potentially split one Stratocaster::Event into multiple paylods to be
      # sent to Octolytics.
      def payloads
        payload = @strat_event.current_payload.with_indifferent_access

        case @strat_event.kind
        when "push"
          # each commit is separated into its own event so that massive pushes
          # are split apart and so commit-level analytics are more easily
          # possible
          if (commits = payload.delete("commits")) && commits.any?
            commits.map { |c| payload.merge(c) }
          elsif (shas = payload.delete("shas")) && shas.any?
            shas.map do |s|
              author = { "email" => s[1], "name" => s[3] }
              payload.merge("sha" => s[0], "author" => author, "message" => s[2])
            end
          else
            [payload]
          end
        when "gollum"
          # Gollum events contain a list of pages that were modified along with
          # the `summary` message for each one. An issue arose when a repo began
          # using automated processes to modify hundreds of pages at a time
          # with a `summary` message that was 64kb. This resulted in message
          # payloads up to, and in excess, of 20MB which is too large to send to
          # octolytics.
          #
          # See: https://github.com/github/github/issues/104711
          payload.delete("pages")
          [payload]
        else
          [payload]
        end
      end
    end
  end
end
