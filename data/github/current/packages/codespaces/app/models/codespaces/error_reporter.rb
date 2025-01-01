# typed: true
# frozen_string_literal: true

module Codespaces
  class ErrorReporter
    attr_reader :reporter

    def initialize(reporter: Failbot, app: "github")
      @reporter = reporter
      @app = app
    end

    def self.report(error, **payload)
      new.report(error, **payload)
    end

    def self.push(**payload, &block)
      new.push(**payload, &block)
    end

    # Wrapper around `Failbot.report`.
    #
    # @param [Codespace] codespace The codespace context for the error. Will automatically be normalized
    # @param [Codespace::Plan] plan The plan context for the error.
    # @param [User] user The user involved with the error
    # @param [User] owner The owner of the plan. Can be an Organization as well.
    # @param [Hash] payload Remaining data will be passed through to Failbot
    #
    # Most data provided will automatically be normalized with the Payload class
    # to extract as much contextual data to provide to Failbot as possible. Any
    # explicitly provided data takes precedence over inferred data.
    def report(error, **payload)
      reporter.report(error, Payload.new(**payload, app: @app).normalize)
    end

    # Wrapper around `Failbot.push`.
    #
    # @param [Codespace] codespace The codespace context for the error. Will automatically be normalized
    # @param [Codespace::Plan] plan The plan context for the error.
    # @param [User] user The user involved with the error
    # @param [User] owner The owner of the plan. Can be an Organization as well.
    # @param [Hash] payload Remaining data will be passed through to Failbot
    #
    # Most data provided will automatically be normalized with the Payload class
    # to extract as much contextual data to provide to Failbot as possible. Any
    # explicitly provided data takes precedence over inferred data.
    def push(**payload, &block)
      reporter.push(Payload.new(**payload).normalize, &block)
    end

    class Payload
      attr_reader :payload, :codespace, :plan, :owner

      def initialize(codespace: nil, plan: nil, user: nil, owner: nil, **payload)
        @payload   = payload
        @codespace = codespace
        @plan      = plan
        @owner     = owner
        @plan     ||= @codespace.plan if @codespace
        @owner    ||= user
        @owner    ||= @codespace.owner if @codespace
      end

      def normalize
        add_owner_details!
        add_plan_details!
        add_codespace_details!
        payload.compact
      end

      private

      def add_owner_details!
        return unless owner

        case owner
        when Organization
          # NOTE: This _has_ to come first because Organization inherits from User
          # Guessing on what to log if we have an Organization owner for now
          payload["gh.organization.id"] ||= owner.id
        when User
          payload["gh.user.id"] ||= owner.id # rubocop:disable GitHub/DoNotAllowLogin
          payload["gh.user.is_staff"] ||= owner.employee?
        end
      end

      def add_plan_details!
        return unless plan

        payload.reverse_merge!(
          "gh.codespaces.plan.id" => plan.id,
          "gh.codespaces.plan.name" => plan.name
        )
      end

      def add_codespace_details!
        return unless codespace

        payload.reverse_merge!(
          "gh.codespaces.id"                   => codespace.id,
          "gh.codespaces.guid"                 => codespace.guid,
          "gh.repo.id"                         => codespace.repository_id,
          "gh.codespaces.region"               => codespace.location,
          "gh.codespaces.sku_name"             => codespace.sku_name,
          "gh.codespaces.vscs_target"          => codespace.vscs_target,
          "gh.codespaces.copilot_workspace_id" => codespace.copilot_workspace_id,
          "gh.codespaces.spark_workbench_id"   => codespace.spark_workbench_id,
        ).compact!
      end
    end
  end
end
