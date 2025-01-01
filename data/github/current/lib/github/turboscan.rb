# typed: strict
# frozen_string_literal: true

require "github/turboscan_connection"
require "github/turboscan_uploaders/i_uploader"
require "github/turboscan_uploaders/azure"
require "github/turboscan_uploaders/s3"
require "turboscan"
require "sarif"
require "date"

class Turboscan::Proto::Result
  extend T::Sig
  # used by calc_last_modified
  sig { returns(Time) }
  def last_modified_at
    T.must(updated_at).to_time
  end
end

module GitHub
  class Turboscan
    extend T::Sig
    extend Scientist

    UPLOAD_MAX_SIZE = T.let(10.megabytes, Integer)
    SARIF_MAX_SIZE = T.let(400.megabytes, Integer)

    CLOSED_REASONS = T.let({
      FALSE_POSITIVE: T.let("false positive", String),
      WONT_FIX: T.let("won't fix", String),
      USED_IN_TESTS: T.let("used in tests", String)
    }.freeze,  T::Hash[Symbol, String])

    RESOLUTION_NOTE_MAX_LENGTH = 280

    PROTOBUF_HASH = T.let(begin
      hash = ""
      protobuf_location = Object.const_source_location("Turboscan::Proto")
      if protobuf_location.present?
        protobuf_file_path, _ = protobuf_location
        begin
          hash = Digest::SHA256.file(protobuf_file_path).hexdigest
        rescue Errno::ENOENT, Errno::EACCES
          # It's better to not fail in this case and just use an empty hash key.
        end
      end
      hash
    end, String)

    # Returns the twirp's client content type
    # In tests, we use VCR cassettes, which were built
    # using application/json content type, therefor, we need to
    # respect that.
    sig { returns(String) }
    def self.client_content_type
      return "application/json" if Rails.env.test?
      "application/protobuf"
    end

    sig { returns(::Faraday::Connection) }
    def self.connection
      @connection ||= T.let(GitHub::TurboscanConnection.new_connection(twirp_service: "Results"), T.nilable(::Faraday::Connection))
    end

    sig { params(options: T::Hash[Symbol, T.untyped], ignored_errors: T::Array[Symbol], block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def self.with_reporting(options: {}, ignored_errors: [:not_found], &block)
      # If this is a repo-scoped request, lookup the owner name for improved telemetry
      if options[:repository_id].present?
        repo = Repository.find_by(id: options[:repository_id])
        owner_name = repo&.owner&.name
        if owner_name.present?
          GitHub.context.push(owner_name: owner_name)
        end
      end

      response = yield

      # response could be nil, a normal response or a promise.
      # 'then' will work in any of these cases.
      response.then do |resp|
        if resp.nil?
          send_message_to_failbot("Nil response from turboscan")
        elsif resp.error && !ignored_errors.include?(resp.error.code)
          send_message_to_failbot("Error response from turboscan: #{resp.error.msg}")
        end
        resp
      end
      if response.respond_to?(:rescue)
        response = response.rescue do |error|
          Failbot.report(error)
        end
        nil
      end
      response
    rescue RuntimeError, Faraday::TimeoutError, Faraday::SSLError, Faraday::Error, Faraday::ConnectionFailed => e
      Failbot.report(e)
      nil
    end

    sig { params(msg: String).void }
    def self.send_message_to_failbot(msg)
      error = StandardError.new msg
      error.set_backtrace(caller)
      Failbot.report(error)
    end

    # see also test/test_helpers/turboscan.rb
    # where this client is modified to run on application/json
    # to make VCRs easier to debug
    sig { returns(::Turboscan::ResultsClient) }
    def self.client
      @client ||= T.let(::Turboscan::ResultsClient.new(
        connection,
        { content_type: client_content_type }
      ), T.nilable(::Turboscan::ResultsClient))
    end

    module ManagedAnalyses
      extend T::Sig

      sig { returns(::Turboscan::ManagedAnalysesClient) }
      def self.client
        @client ||= T.let(::Turboscan::ManagedAnalysesClient.new(
          ::GitHub::TurboscanConnection.new_connection(twirp_service: "ManagedAnalyses"),
          { content_type: ::GitHub::Turboscan::client_content_type },
        ), T.nilable(::Turboscan::ManagedAnalysesClient))
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetManagedAnalysisInfoResponse)])) }
      def self.get_managed_analysis_info(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.get_managed_analysis_info(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::EnableResponse)])) }
      def self.enable(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.enable(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::DisableResponse)])) }
      def self.disable(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.disable(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::UpdateResponse)])) }
      def self.update(options)
        ::GitHub::Turboscan::with_reporting(options: options, ignored_errors: [:already_exists]) { client.update(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::UpdateLanguagesResponse)])) }
      def self.update_languages(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.update_languages(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AdjustResponse)])) }
      def self.adjust(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.adjust(options) }
      end
    end

    module Insights
      extend T::Sig

      sig { returns(::Turboscan::Proto::InsightsClient) }
      def self.client
        @client ||= T.let(::Turboscan::Proto::InsightsClient.new(
          ::GitHub::TurboscanConnection.new_connection(twirp_service: "Insights"),
          { content_type: ::GitHub::Turboscan::client_content_type },
        ), T.nilable(::Turboscan::Proto::InsightsClient))
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse)])) }
      def self.get_alerts_for_insights_backfill(options)
        ::GitHub::Turboscan::with_reporting(options:) { client.get_alerts_for_insights_backfill(options) }
      end
    end

    module SuggestedFixes
      extend T::Sig

      sig { returns(::Turboscan::SuggestedFixesClient) }
      def self.client
        @client ||= T.let(::Turboscan::SuggestedFixesClient.new(
          ::GitHub::TurboscanConnection.new_connection(twirp_service: "SuggestedFixes"),
          { content_type: ::GitHub::Turboscan::client_content_type },
        ), T.nilable(::Turboscan::SuggestedFixesClient))
      end

      sig { returns(::Turboscan::SuggestedFixesClient) }
      def self.async_client
        @async_client ||= T.let(::Turboscan::SuggestedFixesClient.new(
          ::GitHub::TurboscanConnection.async_connection(twirp_service: "SuggestedFixes"),
          { content_type: ::GitHub::Turboscan::client_content_type },
        ), T.nilable(::Turboscan::SuggestedFixesClient))
      end

      sig { returns(::Turboscan::SuggestedFixesClient) }
      def self.patient_client
        @patient_client ||= T.let(::Turboscan::SuggestedFixesClient.new(
          ::GitHub::TurboscanConnection.patient_connection(twirp_service: "SuggestedFixes"),
          { content_type: ::GitHub::Turboscan::client_content_type },
        ), T.nilable(::Turboscan::SuggestedFixesClient))
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetSuggestedFixResponse)])) }
      def self.suggested_fix(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.get_suggested_fix(options) }
      end

      sig do
        params(options: T::Hash[Symbol, T.untyped]).returns(
        Promise[T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GenerateSuggestedFixResponse)])]
      )
      end
      def self.async_suggested_fix(options)
        ::GitHub::Turboscan::with_reporting(options: options) { async_client.get_suggested_fix(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GenerateSuggestedFixResponse)])) }
      def self.generate_suggested_fix(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.generate_suggested_fix(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GenerateSuggestedFixesForReposResponse)])) }
      def self.generate_suggested_fixes_for_repos(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.generate_suggested_fixes_for_repos(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::DismissSuggestedFixResponse)])) }
      def self.dismiss_suggested_fix(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.dismiss_suggested_fix(options) }
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::ApplySuggestedFixResponse)])) }
      def self.apply_suggested_fix(options)
        ::GitHub::Turboscan::with_reporting(options: options) { client.apply_suggested_fix(options) }
      end

      sig do
        params(options: T::Hash[Symbol, T.untyped])
        .returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetSuggestedFixStatisticsResponse)]))
      end
      def self.suggested_fix_statistics(options)
        ::GitHub::Turboscan::with_reporting(options: options) { patient_client.get_suggested_fix_statistics(options) }
      end
    end

    sig { returns(::Faraday::Connection) }
    def self.async_connection
      @async_connection ||= T.let(GitHub::TurboscanConnection.async_connection(twirp_service: "Results"), T.nilable(::Faraday::Connection))
    end

    sig { returns(::Turboscan::ResultsClient) }
    def self.async_client
      @async_client ||= T.let(::Turboscan::ResultsClient.new(
        async_connection,
        { content_type: client_content_type },
      ), T.nilable(::Turboscan::ResultsClient))
    end

    # The patient_client supports a longer timeout than the standard client.
    sig { returns(::Turboscan::ResultsClient) }
    def self.patient_client
      @patient_client_connection ||= T.let(GitHub::TurboscanConnection.patient_connection(twirp_service: "Results"), T.nilable(::Faraday::Connection))
      @patient_client ||= T.let(::Turboscan::ResultsClient.new(@patient_client_connection, { content_type: client_content_type }), T.nilable(::Turboscan::ResultsClient))
    end

    sig { returns(GitHub::TurboscanUploaders::IUploader) }
    def self.storage
      @storage ||= T.let(GitHub.turboscan_azure_account_name.present? ? GitHub::TurboscanUploaders::Azure.new : GitHub::TurboscanUploaders::S3.new, T.nilable(GitHub::TurboscanUploaders::IUploader))
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsResponse)])) }
    def self.alerts(options)
      with_reporting(options: options) { client.get_alerts(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
      Promise[T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsResponse)])]
    )
    end
    def self.async_alerts(options)
      with_reporting(options: options) { async_client.get_alerts(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CountsResponse)])) }
    def self.counts(options)
      with_reporting(options: options) { client.get_counts(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CountsByToolResponse)])) }
    def self.counts_by_tool(options)
      with_reporting(options: options) { client.get_counts_by_tool(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
        T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertResponse)])
      )
    end
    def self.alert(options)
      with_reporting(options: options) { client.get_alert(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
      Promise[T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertResponse)])]
    )
    end
    def self.async_alert(options)
      with_reporting(options: options) { async_client.get_alert(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertTitlesResponse)])) }
    def self.alert_titles(options)
      with_reporting(options: options) { client.get_alert_titles(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertInstancesResponse)])) }
    def self.instances(options)
      with_reporting(options: options) { client.get_alert_instances(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
        T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CodePathsResponse)])
      )
    end
    def self.code_paths(options)
      with_reporting(options: options) { client.get_code_paths(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
        T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::TimelineEventsResponse)])
      )
    end
    def self.timeline_events(options)
      with_reporting(options: options) { client.get_timeline_events(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::SetAlertsStatusResponse)])) }
    def self.set_alerts_status(options)
      with_reporting(options: options) { client.set_alerts_status(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::RulesResponse)])) }
    def self.rules(options)
      with_reporting(options: options) { client.get_rules(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::RuleTagsResponse)])) }
    def self.rule_tags(options)
      with_reporting(options: options) { client.get_rule_tags(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::PullRequestAlertsResponse)])) }
    def self.pull_request_alerts(options)
      with_reporting(options: options) { client.pull_request_alerts(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::PullRequestIntroducedAlertsResponse)])) }
    def self.pull_request_introduced_alerts(options)
      with_reporting(options: options) { client.pull_request_introduced_alerts(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AnnotationsResponse)])) }
    def self.annotations(options)
      with_reporting(options: options) { client.annotations(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
      Promise[T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AnnotationsResponse)])]
    )
    end
    def self.async_annotations(options)
      with_reporting(options: options) { async_client.annotations(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AnalysisResponse)])) }
    def self.analysis(options)
      with_reporting(options: options) { client.get_analysis(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::DeleteAnalysisResponse)])) }
    def self.delete_analysis(options)
      with_reporting(options: options, ignored_errors: [:not_found, :invalid_argument]) do
        client.delete_analysis(options)
      end
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AnalysisSarifResponse)])) }
    def self.analysis_sarif(options)
      with_reporting(options: options) { patient_client.get_analysis_sarif(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AnalysesResponse)])) }
    def self.analyses(options)
      with_reporting(options: options) { client.get_analyses(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::AlertsByRepoResponse)])) }
    def self.alerts_by_repo(options)
      with_reporting(options: options) { client.get_alerts_by_repo(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::ToolNamesResponse)])) }
    def self.tool_names_for_org(options)
      with_reporting(options: options) { client.get_tool_names_for_org(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::RulesForOrgResponse)])) }
    def self.rules_for_org(options)
      with_reporting(options: options) { client.get_rules_for_org(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::RepositoryIDsResponse)])) }
    def self.repository_ids_for_org(options)
      with_reporting(options: options) { client.get_repository_i_ds_for_org(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::SeveritiesForOrgResponse)])) }
    def self.severities_for_org(options)
      with_reporting(options: options) { client.get_severities_for_org(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CountsByRepoNumbersResponse)])) }
    def self.counts_by_repo_numbers(options)
      with_reporting(options: options) { client.get_counts_by_repo_numbers(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::DeliveryResponse)])) }
    def self.get_delivery(options)
      with_reporting(options: options) { client.get_delivery(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CreateDeliveryResponse)])) }
    def self.create_delivery(options)
      with_reporting(options: options) { client.create_delivery(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::EvalRefUpdateRulesResponse)])) }
    def self.eval_ref_update_rules(options)
      ::GitHub::Turboscan::with_reporting(options: options) { client.eval_ref_update_rules(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::CreateAlertLinksResponse)])) }
    def self.create_alert_links(options)
      ::GitHub::Turboscan::with_reporting(options: options) { client.create_alert_links(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetLinksForAlertsResponse)])) }
    def self.get_links_for_alerts(options)
      ::GitHub::Turboscan::with_reporting(options: options) { client.get_links_for_alerts(options) }
    end

    class ResponseError < StandardError
      extend T::Sig

      sig { returns(Twirp::Error) }
      attr_reader :error

      sig { params(error: Twirp::Error).void }
      def initialize(error)
        @error = T.let(error, Twirp::Error)
        super(error.msg)
      end
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
        T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::ToolStatusResponse)])
      )
    end
    def self.get_tool_status(options)
      with_reporting(options: options) do
        response = patient_client.get_tool_status(options)
        raise ::GitHub::Turboscan::ResponseError.new(response.error) unless response.error.nil?
        return Twirp::ClientResp.new(data: ::Turboscan::Proto::ToolStatusResponse.decode_json(response.data.to_json), error: nil)
      rescue ::GitHub::Turboscan::ResponseError => e
        return Twirp::ClientResp.new(data: nil, error: e.error)
      end
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::FilesExtractedSummaryResponse)])) }
    def self.get_files_extracted_summary(options)
      with_reporting(options: options) do
        # a version number based on the protobuf hash and a version we can bump if we need to invalidate the cache manually
        version = "#{PROTOBUF_HASH}/0"
        repository_id = options[:repository_id]
        # make sure the key will not overflow for very long refs by hashing it
        ref = Digest::SHA256.hexdigest(options[:ref])
        tool = Digest::SHA256.hexdigest(options[:tool])
        revision = Repository::CodeScanningDependency::AnalysisRevision.new(repository_id).count
        key = "code_scanning:tool_status/#{version}/#{repository_id}/summary/#{revision}/#{ref}/#{tool}"

        cached = GitHub.cache.fetch(key, force: Rails.env.development?) do
          response = patient_client.get_files_extracted_summary(options)
          raise ::GitHub::Turboscan::ResponseError.new(response.error) unless response.error.nil?
          response.data.to_json
        end

        return Twirp::ClientResp.new(data: ::Turboscan::Proto::FilesExtractedSummaryResponse.decode_json(cached), error: nil)
      rescue ::GitHub::Turboscan::ResponseError => e
        return Twirp::ClientResp.new(data: nil, error: e.error)
      end
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::FilesExtractedResponse)])) }
    def self.get_files_extracted(options)
      with_reporting(options: options) { patient_client.get_files_extracted(options) }
    end

    sig do
      params(options: T::Hash[Symbol, T.untyped]).returns(
        T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::ToolStatusRulesResponse)])
      )
    end
    def self.get_tool_status_rules(options)
      with_reporting(options: options) { patient_client.get_tool_status_rules(options) }
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::GetCodeScanningEnabledResponse)])) }
    def self.code_scanning_enabled?(options)
      with_reporting(options: options) { client.get_code_scanning_enabled(options) }
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], is_empty: T::Boolean).void }
    def self.delivery_invalid_zip_error(repo, params, is_empty:)
      create_delivery_error(repo, params, invalid_zip_error: { empty: is_empty })
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], max: Integer).void }
    def self.delivery_sarif_too_big_error(repo, params, max:)
      create_delivery_error(repo, params, sarif_too_big_error: { max: ActiveSupport::NumberHelper.number_to_human_size(max) })
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], max: Integer).void }
    def self.delivery_zip_too_big_error(repo, params, max:)
      create_delivery_error(repo, params, zip_too_big_error: { max: ActiveSupport::NumberHelper.number_to_human_size(max) })
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], message: String).void }
    def self.delivery_invalid_sarif_error(repo, params, message:)
      create_delivery_error(repo, params, invalid_sarif_error: { message: message })
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], rest: T::Hash[Symbol, T.untyped]).void }
    def self.create_delivery_error(repo, params, **rest)
      create_delivery_for_upload(repo, params, "", rejected: true, **rest)
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], sarif_path: String, kwargs: T.any(T::Boolean, Integer, String, T::Hash[T.untyped, T.untyped])).void }
    def self.create_delivery_for_upload(repo, params, sarif_path, **kwargs)
      started_at = Time.parse(params[:started_at]) if params[:started_at]
      create_delivery_response = self.create_delivery(
        commit_oid: params[:commit_oid],
        ref: params[:ref],
        repository_id: repo.id,
        repository_nwo: repo.nwo,
        sarif_id: params[:sarif_id],
        request_id: params[:request_id],
        analysis_name: params[:analysis_name],
        analysis_key: params[:analysis_key],
        environment: params[:environment],
        checkout_uri: params[:checkout_uri],
        build_started_at: started_at,
        workflow_run_id: params[:workflow_run_id],
        workflow_run_attempt: params[:workflow_run_attempt],
        upload_started_at: params[:upload_started_at],
        upload_finished_at: params.fetch(:upload_finished_at, Time.now),
        hydro_enqueued_at: Time.now,
        sarif_path: sarif_path,
        source_repository_id: params[:source_repository_id],
        outdated_configuration: params[:outdated_configuration],
        **kwargs,
      )
      if create_delivery_response.nil? || create_delivery_response.error.present?
        # We don't fail if creating the delivery fails.
        # This allows us to still accept uploads even if TurboScan is down.
        # Pull requests from forks may not be able to check their status if this occurs, but other analyses shouldn't be disrupted.
        Failbot.report(StandardError.new("Could not create delivery synchronously: #{create_delivery_response&.error}"))
      end
    end

    class ValidatedAnalysis < T::Struct
      extend T::Sig

      const :gzip, String
      const :tool_names, T::Array[String], default: []

      sig { override.returns(String) }
      def inspect
        "ValidatedAnalysis(gzip: #{gzip.size} bytes, tool_names: #{tool_names})"
      end
    end

    class GzipTooLargeError < StandardError
    end

    class NoSarifToolsError < StandardError
    end

    sig { params(repo: Repository, sarif: String, use_jsonschema: T::Boolean).returns(ValidatedAnalysis) }
    def self.validate_sarif(repo, sarif, use_jsonschema:)
      gzip = Base64.decode64(sarif)
      if gzip.size > UPLOAD_MAX_SIZE
        raise GzipTooLargeError.new("Gzipped SARIF is too large")
      end
      tool_names = ::Sarif.parse(gzip, use_jsonschema, SARIF_MAX_SIZE).map { |run| run[:name] }.uniq
      if tool_names.empty?
        raise NoSarifToolsError.new("Invalid SARIF document: Empty sarif file provided.")
      end
      ValidatedAnalysis.new(gzip:, tool_names:)
    end

    sig { params(repo: Repository, params: T::Hash[Symbol, T.untyped], sarif: T.nilable(ValidatedAnalysis)).returns(T::Hash[Symbol, String]) }
    def self.upload_analysis(repo, params, sarif)
      uri = ""
      sarif_id = params[:sarif_id]
      # in order to keep code paths the same, we skip actual sarif upload when marking as outdated
      unless sarif.nil?
        GitHub.logger.info(
          "Starting to upload the sarif file",
          "code.namespace" => "CodeScanning",
          "code.function" => "upload_analysis",
          "gh.repo.id" => repo.id,
          "gh.code_scanning.tools" => sarif.tool_names,
          "gh.code_scanning.sarif.id" => sarif_id,
          "gh.code_scanning.sarif.size" => sarif.gzip.size,
        )

        uri = self.storage.upload(sarif.gzip, generate_upload_path(repo, sarif_id))
      end
      self.create_delivery_for_upload(repo, params, uri)
      GitHub.logger.info(
        "Sending new analysis message to Hydro",
        "code.namespace" => "CodeScanning",
        "code.function" => "upload_analysis",
        "gh.repo.id" => repo.id,
        "gh.code_scanning.sarif.uri" => uri,
      )
      self.send_hydro_msg(repo, params, uri)
      GitHub.logger.info(
        "Finished sending new analysis message to Hydro",
        "code.namespace" => "CodeScanning",
        "code.function" => "upload_analysis",
        "gh.repo.id" => repo.id,
        "gh.code_scanning.sarif.uri" => uri,
      )
      { id: sarif_id }
    end

    sig { params(request_id: String, repo: Repository, tool_name: String, ref: String, category: String).returns(T::Hash[Symbol, T.any(T::Hash[Symbol, T.any(String, Symbol)], String)]) }
    def self.create_outdated_analysis(request_id, repo, tool_name, ref, category)
      # creates a "tombstone" analysis for a configuration that is no longer useful to the user (stale alerts etc.)
      head = repo.heads.async_find(ref).sync
      analysis_key = category
      if category.empty?
        analysis_key = "(default)"
      end
      params = {
        request_id: request_id,
        source_repository_id: repo.id,
        ref: head.qualified_name,
        commit_oid: head.target_oid,
        analysis_key: analysis_key,
        outdated_configuration: { category: category, tool_name: tool_name },
        started_at: Time.now.iso8601,
        upload_started_at: Time.now,
        upload_finished_at: Time.now,
        sarif_id: SimpleUUID::UUID.new.to_guid.to_s,
        track_status: repo.default_branch == ref.delete_prefix("refs/heads/")
      }

      self.upload_analysis(repo, params, nil)
    end

    sig { params(io: StringIO).returns(T::Boolean) }
    private_class_method def self.gzip_empty?(io)
      reader = Zlib::GzipReader.new(io)
      begin
        return true if reader.eof?
        # Try and read a byte and rescue the exception if the zipfile looks corrupt.
        #
        # Note: Reading a single byte like this is okay, but you shouldn't
        # decompress a complete user-provided zip file without guarding
        # against zipbombing.
        reader.getbyte
      rescue Zlib::GzipFile::Error
        return true
      ensure
        reader.close
      end

      false
    end

    sig { params(repo: Repository, guid: String).returns(String) }
    def self.generate_upload_path(repo, guid)
      "upload/#{repo.id}/#{guid}.sarif.gz"
    end

    sig { params(repo: Repository, params: T::Hash[T.any(Symbol, String), T.untyped], uri: String).void }
    def self.send_hydro_msg(repo, params, uri)
      started_at = Time.parse(params["started_at"]) if params["started_at"]

      args = {
        repository_id: repo.id,
        sarif_uri: uri,
        sarif_id: params[:sarif_id],
        commit_oid: params[:commit_oid],
        ref: params[:ref],
        analysis_name: params[:analysis_name],
        environment: params[:environment],
        checkout_uri: params[:checkout_uri],
        build_start_at: started_at,
        workflow_run_id: params[:workflow_run_id],
        workflow_run_attempt: params[:workflow_run_attempt],
        analysis_key: params[:analysis_key],
        upload_started_at: params[:upload_started_at],
        upload_finished_at: params[:upload_finished_at],
        hydro_enqueued_at: Time.now,
        request_id: params[:request_id],
        repo_nwo: repo.nwo,
        source_repository_id: params[:source_repository_id],
        check_run_ids: params[:check_run_ids],
        track_status: params[:track_status],
        outdated_configuration: params[:outdated_configuration],
        explicit_enablement_enforced: params[:explicit_enablement_enforced],
        advanced_setup_enabled: params[:advanced_setup_enabled],
        third_party_tools_enabled: params[:third_party_tools_enabled],
      }

      GitHub.dogstats.increment("turboscan_client.upload_analysis")
      GlobalInstrumenter.instrument("code_scanning.new_analysis", args)
    end

    sig { params(outdated_configuration: T.nilable(T::Hash[Symbol, String])).returns(::Turboscan::Proto::OutdatedConfiguration) }
    def self.to_outdated_configuration(outdated_configuration)
      if outdated_configuration
        ::Turboscan::Proto::OutdatedConfiguration.new(
          category: outdated_configuration[:category],
          tool_name: outdated_configuration[:tool_name]
        )
      else
        ::Turboscan::Proto::OutdatedConfiguration.new
      end
    end

    sig { params(rule_severity: String).returns(T.nilable(Integer)) }
    def self.to_rule_severity(rule_severity)
      rule_severity = rule_severity.to_s.to_sym.upcase
      resolved_rule_severity = ::Turboscan::Proto::RuleSeverity.resolve(rule_severity)
      if resolved_rule_severity != ::Turboscan::Proto::RuleSeverity::NONE
        resolved_rule_severity
      end
    end

    sig { params(rule_severity: String).returns(T.nilable(Integer)) }
    def self.to_security_severity(rule_severity)
      rule_severity = rule_severity.to_s.to_sym.upcase
      resolved_security_severity = ::Turboscan::Proto::SecuritySeverity.resolve(rule_severity)
      if resolved_security_severity != ::Turboscan::Proto::SecuritySeverity::NO_SECURITY_SEVERITY
        resolved_security_severity
      end
    end

    sig { params(resolution_filter_value: String).returns(T.nilable(Integer)) }
    def self.to_resolution_filter(resolution_filter_value)
      resolution = if resolution_filter_value.downcase == "fixed"
        # Alerts fixed (as opposed to closed by user)
        # don't have a manual resolution type set
        :FILTER_NO_RESOLUTION
      else
        ("FILTER_" + resolution_filter_value.upcase.gsub("-", "_")).to_sym
      end
      resolved_resolution = ::Turboscan::Proto::ResultResolutionFilter.resolve(resolution)
      if resolved_resolution != ::Turboscan::Proto::ResultResolutionFilter::FILTER_NONE
        resolved_resolution
      end
    end

    # Get the tool names as an Arrray of strings
    # Will return nil if turboscan is down, or no results found
    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Array[String])) }
    def self.tool_names(options)
      with_reporting(options: options) do
        client.tool_names(options)
      end&.data&.tools&.map(&:name)
    end

    sig { params(resolution: T.any(Symbol, String)).returns(T.nilable(Integer)) }
    def self.to_resolution(resolution)
      resolution = resolution.to_s.to_sym.upcase
      resolved = ::Turboscan::Proto::ResultResolution.resolve(resolution)
      if resolved != ::Turboscan::Proto::ResultResolution::NO_RESOLUTION
        resolved
      end
    end

    sig { params(visibility: String).returns(T.nilable(Integer)) }
    def self.to_repository_visibility(visibility)
      return if visibility.nil?
      visibility = "repository_visibility_#{visibility}".to_sym.upcase
      resolved = ::Turboscan::Proto::RepositoryVisibility.resolve(visibility)

      resolved if resolved != ::Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_UNKNOWN
    end

    sig { params(autofilter_value: String).returns(T.nilable(Integer)) }
    def self.to_classification_filter(autofilter_value)
      # `autofilter:true` means "exclude classified alerts"
      # So if `autofilter:true` is supplied, then we only want
      # Turboscan to return alerts without a classification,
      # hence ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED
      #
      # "Classified" alerts are those found in test code, library
      # code, generated code, etc.
      if autofilter_value == "true"
        ::Turboscan::Proto::AlertClassificationFilter::ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED
      end
    end

    sig { params(reason: Symbol).returns(T.nilable(String)) }
    def self.api_resolution_reason(reason)
      CLOSED_REASONS[reason]
    end

    sig { params(reason: String).returns(T.nilable(Symbol)) }
    def self.resolution_reason_sym(reason)
      CLOSED_REASONS.invert[reason]
    end

    sig { params(state: T.nilable(String)).returns(Integer) }
    def self.to_alert_state_filter(state)
      # mangle the state string into a namespaced form
      case state
      when "dismissed"
        # 'resolved' is turboscan terminology for what we call 'dismissed' in the API
        state = "closed_resolved"
      when "fixed"
        state = "closed_fixed"
      end
      state = "alert_state_filter_#{state}"

      # default to all alerts
      ::Turboscan::Proto::AlertStateFilter.resolve(state.to_sym.upcase) ||
        ::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_ALL
    end

    # Used for API sorting (as that is based on two values)
    sig { params(sort: T.nilable(String), direction: T.nilable(String)).returns(Symbol) }
    def self.api_to_alert_sort_order(sort, direction)
      sort = "CREATED" unless sort&.upcase == "UPDATED"

      :"#{T.must(sort).upcase}_#{convert_api_sort_direction(direction)}"
    end

    sig { params(sort: T.nilable(String), direction: T.nilable(String)).returns(Symbol) }
    def self.api_to_analyses_sort_order(sort, direction)
      # sort is always CREATED for analyses, but that parameter is accepted for consistency with alerts
      :"ANALYSES_CREATED_#{convert_api_sort_direction(direction)}"
    end

    sig { params(direction: T.nilable(String)).returns(String) }
    def self.convert_api_sort_direction(direction)
      direction_string = case direction&.downcase
      when "asc"
        "ASCENDING"
      when "desc"
        "DESCENDING"
      else
        "DESCENDING"
      end
    end

    sig { params(severity: String).returns(T.nilable(Integer)) }
    def self.to_severity(severity)
      sev_string = "SEVERITY_" + severity.upcase
      resolved_severity = ::Turboscan::Proto::Severity.resolve(sev_string.to_sym)
      if resolved_severity != ::Turboscan::Proto::Severity::NO_SEVERITY
        resolved_severity
      end
    end

    sig { params(comment: T.nilable(String)).returns(T.nilable(String)) }
    def self.normalize_dismissed_comment(comment)
      return nil if comment.nil?
      comment.encode("UTF-8", universal_newline: true)
    end

    sig { params(comment: T.nilable(String)).returns(T::Boolean) }
    def self.dismissed_comment_valid?(comment)
      return true if comment.nil?
      return false if comment.length > RESOLUTION_NOTE_MAX_LENGTH
      true
    end
  end
end
