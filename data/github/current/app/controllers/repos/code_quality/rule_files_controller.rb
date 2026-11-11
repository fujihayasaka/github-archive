# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFilesController < Repos::CodeQuality::BaseRepositoryController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :check_code_quality_read

  sig { void }
  def index
    rule_id = params[:rule_id].to_s

    response = GitHub::Turboquality.client.file_results(Turboquality::Proto::FileResultsRequest.new(
      repository_id: current_repository.id,
      rule_id:,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    files = serialized_files(response.data.files.to_a)
    payload = {
      files: files.take(5),
      totalCount: response.data.count,
    }
    render json: payload, status: :ok
  end

  private

  sig { params(files: T::Array[Turboquality::Proto::FileResult]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_files(files)
    files.map do |file|
      {
        filePath: file.file_path,
        findingsCount: file.result_count,
      }
    end
  end
end
