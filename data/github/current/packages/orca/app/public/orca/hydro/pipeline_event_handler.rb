# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    class PipelineEventHandler < BaseHandler
      extend T::Sig

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
          model_action: "none",
        }, T.nilable(T::Hash[Symbol, String]))

        return unless organization

        case status
        when :COMPLETED
          upsert_model
          email :model_ready
        when :FAILED
          email :model_failed
        when :INACTIVE, :DELETING, :DELETED
          delete_model
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

      sig { void }
      def upsert_model
        unless resource.present? && deployment.present?
          raise Error, "Resource and/or deployment missing"
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          retry_on_find_or_create_error(max_retry_count: 3) do
            model = Orca::Model.find_by(pipeline_id: pipeline_id)

            if model
              model.update(
                resource: resource,
                deployment: deployment
              )

              T.must(@stats_tags)[:model_action] = "update"
            else
              Orca::Model.create(
                pipeline_id: pipeline_id,
                organization: T.must(organization),
                resource: resource,
                deployment: deployment
              )

              T.must(@stats_tags)[:model_action] = "create"
            end
          end
        end
      end

      sig { void }
      def delete_model
        ActiveRecord::Base.connected_to(role: :writing) do
          model = Orca::Model.find_by(pipeline_id: pipeline_id)

          if model
            model.destroy
            T.must(@stats_tags)[:model_action] = "delete"
          end
        end
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

      sig { returns(String) }
      memoize def deployment
        value.dig(:model, :deployment).to_s
      end

      sig { returns(String) }
      memoize def resource
        value.dig(:model, :resource).to_s
      end
    end
  end
end
