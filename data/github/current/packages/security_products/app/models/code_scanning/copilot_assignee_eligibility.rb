# typed: strict
# frozen_string_literal: true

module CodeScanning
  # Captures the rules for assigning Copilot to a code scanning alert.
  # Fetches current alert state from Turboscan and returns a result containing:
  #   - authorized:          whether the assignment is permitted
  #   - new_assignment:      whether Copilot is not yet assigned to the alert
  #   - turboscan_result:    the raw alert state fetched from Turboscan (nil on fetch error)
  #   - autofix_suggestions: suggested fixes keyed by alert number (classic autofix path only)
  #   - fetch_error:         whether the Turboscan fetch failed
  #   - use_cca:             whether agentic autofix (CCA) is enabled for this assignment
  class CopilotAssigneeEligibility
    class Result < T::Struct
      const :authorized, T::Boolean
      const :new_assignment, T::Boolean
      const :turboscan_result, T.nilable(Turboscan::Proto::Result), default: nil
      const :autofix_suggestions, T.nilable(T::Hash[Integer, Turboscan::Proto::SuggestedFixAlert]), default: nil
      const :fetch_error, T::Boolean, default: false
      const :use_cca, T::Boolean, default: false

      sig { returns(T::Boolean) }
      def authorized? = authorized

      sig { returns(T::Boolean) }
      def new_assignment? = new_assignment

      sig { returns(T::Boolean) }
      def fetch_error? = fetch_error

      # Returns true when agentic autofix (CCA) should be started for this assignment:
      # Copilot must be newly assigned, authorized, and the CCA feature must be enabled.
      sig { returns(T::Boolean) }
      def should_start_agentic_autofix? = use_cca && new_assignment? && authorized?

      # Returns true when a classic autofix PR should be opened for this assignment:
      # Copilot must be newly assigned, authorized, and CCA must be disabled.
      sig { returns(T::Boolean) }
      def should_emit_classic_autofix_event? = !use_cca && new_assignment? && authorized?
    end

    sig do
      params(
        repository: Repository,
        user: User,
        alert_number: Integer,
        use_cca: T::Boolean,
      ).returns(Result)
    end
    def self.check(repository:, user:, alert_number:, use_cca:)
      new(repository:, user:, alert_number:, use_cca:).check
    end

    sig do
      params(
        repository: Repository,
        user: User,
        alert_number: Integer,
        use_cca: T::Boolean,
      ).void
    end
    def initialize(repository:, user:, alert_number:, use_cca:)
      @repository = T.let(repository, Repository)
      @user = T.let(user, User)
      @alert_number = T.let(alert_number, Integer)
      @use_cca = T.let(use_cca, T::Boolean)
    end

    sig { returns(Result) }
    def check
      integration = T.let(::Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
      return Result.new(authorized: false, new_assignment: false, fetch_error: true, use_cca: @use_cca) unless integration

      copilot_bot = integration.bot
      return Result.new(authorized: false, new_assignment: false, fetch_error: true, use_cca: @use_cca) unless copilot_bot

      alert_response = GitHub::Turboscan.alert(
        repository_id: @repository.id,
        number: @alert_number,
      )

      result = alert_response&.data&.result
      unless result.present?
        return Result.new(authorized: false, new_assignment: false, fetch_error: true, use_cca: @use_cca)
      end

      turboscan_result = result

      is_new = turboscan_result.assigned_user_ids.none? { |id| id == copilot_bot.id }

      # If Copilot is already assigned, consider it an authorized assignee regardless
      # of other checks. This allows users to control when to unassign it.
      # Since we do not emit the Copilot assignment event when Copilot is already
      # assigned, it is okay to ignore the other checks in this scenario.
      return Result.new(authorized: true, new_assignment: false, turboscan_result:, use_cca: @use_cca) unless is_new

      # If Copilot is being newly assigned, we need to check:
      # * if the user has write access to the repository
      # * if the Copilot SWE agent is enabled for the repository
      # * if there is a suggested fix available for the alert and it is not outdated
      unless @repository.writable_by?(@user) && @repository.copilot_swe_agent_enabled?(@user)
        return Result.new(authorized: false, new_assignment: true, turboscan_result:, use_cca: @use_cca)
      end

      # Agentic autofix will generate the fix using CCA, so we don't
      # need to check for an existing suggested fix in that case.
      if @use_cca
        return Result.new(authorized: true, new_assignment: true, turboscan_result:, use_cca: @use_cca)
      end

      # Classic autofix path: require a non-nil, non-outdated suggested fix.
      autofix_suggestions = fetch_autofix_suggestions(turboscan_result)
      suggested_fix_alert = autofix_suggestions&.[](@alert_number)
      suggested_fix = suggested_fix_alert&.suggested_fix

      if suggested_fix.nil? || suggested_fix.outdated
        return Result.new(authorized: false, new_assignment: true, turboscan_result:, use_cca: @use_cca)
      end

      Result.new(
        authorized: true,
        new_assignment: true,
        turboscan_result:,
        autofix_suggestions:,
        use_cca: @use_cca,
      )
    end

    private

    sig { params(turboscan_result: Turboscan::Proto::Result).returns(T.nilable(T::Hash[Integer, Turboscan::Proto::SuggestedFixAlert])) }
    def fetch_autofix_suggestions(turboscan_result)
      CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
        repository: @repository,
        alert_numbers: [@alert_number],
        head_commit_oid: turboscan_result.most_recent_instance&.commit_oid,
      )
    rescue CodeScanning::AutofixError => e
      Failbot.report!(e)
      nil
    end
  end
end
