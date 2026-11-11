# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    module CustomModel
      class AwsBedrock < T::Struct
        class InferenceType < T::Enum
          enums do
            InferenceProfile = new("INFERENCE_PROFILE")
            OnDemand = new("ON_DEMAND")
          end
        end

        const :inference_type, InferenceType
        const :model_arn, String
        const :inference_policy_arn, T.nilable(String)
        const :inference_policy_regions, T.nilable(T::Array[String])

        sig { params(data_hash: T::Hash[String, T.untyped]).returns(AwsBedrock) }
        def self.build!(data_hash)
          inference_type_str = data_hash["inference_type"]
          model_arn = data_hash["model_arn"]
          inference_policy_arn = data_hash["inference_policy_arn"]
          inference_policy_regions = data_hash["inference_policy_regions"]

          inference_type = case inference_type_str
          when "INFERENCE_PROFILE"
            InferenceType::InferenceProfile
          when "ON_DEMAND"
            InferenceType::OnDemand
          else
            raise Error.new("Inference type must be either 'INFERENCE_PROFILE' or 'ON_DEMAND'")
          end

          if model_arn.nil?
            raise Error.new("model_arn must be provided for AWS Bedrock")
          end

          if inference_type == InferenceType::InferenceProfile
            if inference_policy_arn.nil? || inference_policy_arn.strip.empty?
              raise Error.new("inference_policy_arn must be provided when inference_type is INFERENCE_PROFILE")
            end

            if inference_policy_regions.nil? || inference_policy_regions.empty?
              raise Error.new("inference_policy_regions must be provided when inference_type is INFERENCE_PROFILE")
            end
          end

          new(
            inference_type: inference_type,
            model_arn: model_arn,
            inference_policy_arn: inference_policy_arn,
            inference_policy_regions: inference_policy_regions
          )
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def to_twirp_details
          {
            "inference_type" => inference_type.serialize,
            "model_arn" => model_arn,
            "inference_policy_arn" => inference_policy_arn,
            "inference_policy_regions" => inference_policy_regions
          }
        end

        # Public: Returns a representation of this AWS Bedrock-specific data in a way that can be sent to the
        # frontend.
        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          to_twirp_details.map { |key, value| [key.camelize(:lower), value] }.to_h
        end
      end
    end
  end
end
