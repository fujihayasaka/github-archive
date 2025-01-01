# typed: true
# frozen_string_literal: true

module GitSrcMigrator
  module Service
    class ActionsLogsHelper
      def expired_logs?(workflow_run)
        workflow_run.expired_logs?
      end

      def download_logs_archive_url_from_backend(log_url, check_suite, workflow_run_backend_id, repository_global_id)
        if check_suite.workflow_run.logs_via_results_service?
          return nil if workflow_run_backend_id.nil?

          result = ActionsResults::Twirp.log_client.get_completed_run_log_archive(
            workflow_run_backend_id: workflow_run_backend_id
          )

          redirect_url = if result.call_succeeded?
            result.value.log_url
          else
            nil
          end
        else
          request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
            unauthenticated_url: log_url,
            repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repository_global_id),
            resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_RUN_LOG,
          })

          result = Launch::Twirp.artifacts_exchange_client_for_check_suite(check_suite).exchange_url(request)

          if result.call_succeeded?
            redirect_url = result.value.authenticated_url
          else
            redirect_url = nil
          end
        end

        redirect_url
      end
    end
  end
end
