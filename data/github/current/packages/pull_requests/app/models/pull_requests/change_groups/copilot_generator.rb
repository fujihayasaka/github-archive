# typed: strict
# frozen_string_literal: true

module PullRequests
  module ChangeGroups
    class CopilotGenerator
      include GitHub::Memoizer

      RETRYABLE_COPILOT_API_ERRORS = [
        CopilotAPI::NetworkError,
        CopilotAPI::RateLimitError,
      ].freeze

      class GeneratedGroup < T::Struct
        const :name, String
        const :priority, Integer
        const :bug_risk, Integer
        const :confidence, Integer
        const :hunk_ids, T::Array[Integer]
      end

      module Result
        extend T::Helpers
        sealed!

        requires_ancestor { Object }

        class Error < T::Struct
          include Result
          const :exception, StandardError
          const :copilot_response, Object
          const :retryable, T::Boolean

          sig { params(message: String, copilot_response: Object, retryable: T::Boolean).returns(Error) }
          def self.with_message(message, copilot_response:, retryable:)
            exception = RuntimeError.new(message)
            new(exception:, copilot_response:, retryable:)
          end

          sig { returns(T::Boolean) }
          def retryable? = retryable

          sig { returns(T.noreturn) }
          def raise!
            raise exception
          end

          # Raises the result's exception, then rescues it and re-raises the
          # given `wrapper`. This will produce an exception where the `cause`
          # is set to the original error.
          #
          # For example, in an orchestration we might want to raise a different
          # error type to trigger a retry:
          #
          #     result.raise_as_cause_of!(Orchestration::RetryStepError)
          sig { params(wrapper: T.any(StandardError, T.class_of(StandardError))).returns(T.noreturn) }
          def raise_as_cause_of!(wrapper)
            raise!
          rescue
            case wrapper
            when Exception then raise wrapper
            when Class then raise wrapper.new(exception.message)
            else
              T.absurd(wrapper)
            end
          end
        end

        class Success < T::Struct
          include Result
          const :groups, T::Array[GeneratedGroup]

          extend T::Generic
          include Enumerable
          Elem = type_member { { fixed: GeneratedGroup } }
          delegate :each, to: :groups
        end
      end

      MAX_TOKENS = 1_000 # TODO: Set max tokens
      TEMPERATURE = 0.2 # TODO: Set temperature

      sig { params(actor: User, prompt: PromptBuilder::Result).void }
      def initialize(actor:, prompt:)
        @actor = actor
        @prompt = prompt
      end

      sig { returns(Result) }
      def call
        begin
          copilot_response = copilot_api_client.create_chat_completion(
            model: "gpt-4.1",
            messages: @prompt.messages,
            max_tokens: MAX_TOKENS,
            temperature: TEMPERATURE,
          )

          if copilot_response.is_a?(ConcurrentFaraday::FutureResponse)
            copilot_response = copilot_response.sync
          end
        rescue CopilotAPI::Error => exception
          retryable = RETRYABLE_COPILOT_API_ERRORS.include?(exception.class)
          return Result::Error.new(exception:, copilot_response:, retryable:)
        end

        message = copilot_response.dig("choices", 0, "message", "content") || ""

        if !message.is_a?(String) || message.blank?
          return Result::Error.with_message(
            "Unexpected Copilot response format",
            copilot_response:,
            retryable: true,
          )
        end

        message = message
          .sub(/\A```\s*json\n*/, "")
          .sub(/\n*```\n*\z/, "")

        begin
          data = JSON.parse(message)
        rescue JSON::ParserError => exception
          return Result::Error.new(
            exception:,
            copilot_response: message,
            retryable: true,
          )
        end

        validation_errors = ::JSON::Validator.fully_validate(
          @prompt.expected_response_schema,
          data,
        )
        if validation_errors.any?
          error_desc = validation_errors.join(", ")
          return Result::Error.with_message(
            "Unexpected JSON in response: #{error_desc}",
            copilot_response: data,
            retryable: true,
          )
        end

        groups = data.fetch("semanticGroups", []).map do |group|
          GeneratedGroup.new(
            name: group.fetch("name"),
            hunk_ids: group.fetch("hunkIds"),
            priority: group.fetch("priority"),
            bug_risk: group.fetch("bugRisk"),
            confidence: group.fetch("confidence"),
          )
        end

        group_name_lengths = groups.map { _1.name.length }

        # The amount of padding between the requested group name length used in
        # the prompt and the enforced group name length used in the model will
        # likely need some tuning. This distribution is intended to help with
        # that tuning.
        group_name_lengths.each do |len|
          GitHub.dogstats.distribution(
            "pull_requests.change_groups.generated_group.name_length", len,
            tags: [
              "requested_limit:#{PromptBuilder::PROMPT_MAX_NAME_LENGTH}",
              "enforced_limit:#{ChangeGroup::MAX_NAME_LENGTH}",
            ]
          )
        end

        # The group name length is not enforced by the JSON schema, because
        # LLMs are not very good at sticking exactly to character limits, so
        # the limit we provide in the prompt is a little lower than the one we
        # actually want to enforce.
        if group_name_lengths.any? { |len| len > ChangeGroup::MAX_NAME_LENGTH }
          return Result::Error.with_message(
            "Maximum group name length exceeded #{ChangeGroup::MAX_NAME_LENGTH}",
            copilot_response: data,
            retryable: true,
          )
        end

        Result::Success.new(groups:)
      end

      private

      sig { returns(::Copilot::User::CopilotApi) }
      memoize def copilot_api_client
        ::Copilot::User.copilot_api(
          user: @actor,
          integration_id: CopilotAPI::COPILOT_PR_GROUPS_INTEGRATION_ID,
        )
      end
    end
  end
end
