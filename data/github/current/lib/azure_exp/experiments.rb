# typed: true
# frozen_string_literal: true

module AzureEXP
  module Experiments
    class ExperimentNotFoundError < StandardError; end
    class ExperimentVariantError < StandardError; end

    class Assignments
      extend T::Sig

      attr_accessor :experiments

      def initialize(experiments = nil)
        if experiments.nil?
          @experiments = JSON.parse(File.read("#{Rails.root}/config/experiments.json"), symbolize_names: true).freeze
        else
          @experiments = experiments
        end
      end

      sig { params(user: User, experiment: Symbol, variant: T.nilable(T.any(String, T::Boolean, Integer))).returns(T::Boolean) }
      def assigned?(user, experiment, variant: nil)
        experiment = @experiments[:experiments].find { |e| e[:name] == experiment.to_s }

        unless experiment
          Failbot.report(ExperimentNotFoundError.new("Experiment #{experiment} not found"))
          return false
        end

        if !experiment[:boolean] && variant.nil?
          Failbot.report(ExperimentVariantError.new("Experiment #{experiment} requires a variant"))
          return false
        end

        return false unless GitHub.flipper[experiment[:feature_flag].to_sym].enabled?(user)
        return false unless assigned_variant?(user, experiment, variant)
        true
      end

      private

      sig { params(user: User, experiment: Hash, variant: T.nilable(T.any(String, T::Boolean, Integer))).returns(T::Boolean) }
      def assigned_variant?(user, experiment, variant)
        assignment = assignment(user, experiment[:namespace], experiment[:surface])

        if variant
          assignment.in_group?(group_name: experiment[:id], expected_value: variant)
        else
          assignment.in_group?(group_name: experiment[:id])
        end
      end

      sig { params(user: User, namespace: String, surface: String).returns(AzureEXP::ExpAssignmentProvider) }
      def assignment(user, namespace, surface)
        participant = AzureEXP::Beta::Participant.from_user(user)

        AzureEXP::ExpAssignmentProvider.new(participant:, namespace:, surface:)
      end
    end
  end
end

require "azure_exp/experiments/feeds"
require "azure_exp/experiments/growth"
require "azure_exp/experiments/webex"
