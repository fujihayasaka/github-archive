# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    class PipelineEventHandler < BaseHandler
      include BaseHelpers::Helpers
      include GitHub::Memoizer

      topic "orca.v0.PipelineEvent"

      Error = Class.new(StandardError)

      sig { void }
      def handle
        @stats_tags = T.let({
          status: status.to_s.downcase,
          organization: !!organization,
          email_action: "none",
        }, T.nilable(T::Hash[Symbol, String]))

        return unless organization

        case status
        when :COMPLETED
          email :model_ready
        when :FAILED
          email :model_failed
        end
      ensure
        GitHub.dogstats.increment "github.orca.pipeline_event",
          tags: T.must(@stats_tags).map { |k, v| "#{k}:#{v}" }
      end

      private

      sig { params(action: Symbol).void }
      def email(action)
        case action
        when :model_ready
          CopilotOrcaMailer.model_ready(pipeline_id).deliver_later
        when :model_failed
          CopilotOrcaMailer.model_failed(pipeline_id).deliver_later
        else
          raise ArgumentError, "Unknown email action: #{action}"
        end

        T.must(@stats_tags)[:email_action] = action.to_s
      end

      sig { returns(String) }
      memoize def pipeline_id
        value[:pipeline_id].to_s
      end

      sig { returns(Symbol) }
      memoize def status
        value[:status].to_sym
      end

      sig { returns(T.nilable(Organization)) }
      memoize def organization
        Organization.find_by(id: value.dig(:organization, :id))
      end
    end
  end
end
