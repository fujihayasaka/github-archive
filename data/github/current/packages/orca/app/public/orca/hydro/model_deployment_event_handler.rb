# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    class ModelDeploymentEventHandler < BaseHandler
      include BaseHelpers::Helpers
      include GitHub::Memoizer

      topic "orca.v0.ModelDeploymentEvent"

      Error = Class.new(StandardError)

      sig { void }
      def handle
        @stats_tags = T.let({
          status: status.to_s.downcase,
          usage: usage.to_s.downcase,
          organization: !!organization,
          model_action: "none",
        }, T.nilable(T::Hash[Symbol, String]))

        return unless inference?
        return unless organization

        case status
        when :ACTIVE
          upsert_model
        when :INACTIVE, :DELETING, :DELETED
          delete_model
        end
      ensure
        GitHub.dogstats.increment "github.orca.model_deployment_event",
          tags: T.must(@stats_tags).map { |k, v| "#{k}:#{v}" }
      end

      private

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

      sig { returns(T::Boolean) }
      memoize def inference?
        usage == :INFERENCE
      end

      sig { returns(String) }
      memoize def pipeline_id
        value[:pipeline_id].to_s
      end

      sig { returns(Symbol) }
      memoize def status
        value[:status].to_sym
      end

      sig { returns(Symbol) }
      memoize def usage
        sym = value[:usage].to_sym
        return :UNKNOWN if sym == :UNKNOWN_USAGE
        sym
      end

      sig { returns(String) }
      memoize def deployment
        value[:deployment].to_s
      end

      sig { returns(String) }
      memoize def resource
        value[:resource].to_s
      end

      sig { returns(T.nilable(Organization)) }
      memoize def organization
        Organization.find_by(id: value.dig(:organization, :id))
      end
    end
  end
end
