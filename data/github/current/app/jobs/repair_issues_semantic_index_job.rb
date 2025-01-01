# rubocop:disable GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RepairIssuesSemanticIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  retry_on_dirty_exit

  around_perform do |job, block|
    repo_ids = GitHub
      .flipper[:elasticsearch_semantic_indexing_issues]
      .actors_value
      .to_a
      .select { |v| v.include?("Repository") }
      .map { |v| v.split(":")[1] }

    conditions = if repo_ids.empty?
      "issues.has_pull_request = 0"
    else
      "issues.has_pull_request = 0 AND issues.repository_id IN (#{repo_ids.join(",")})"
    end

    job.class.reconcilers.first[:conditions] = conditions

    if GitHub.flipper[:repair_issues_semantic_index_job_raises_on_errors].enabled?
      if job.arguments.length > 1
        job.arguments[1][:raise_errors] = true
      else
        job.arguments << { raise_errors: true }
      end
    end

    block.call
  end

  reconcile "issue_semantic",
    model_class: Issue,
    fields: %w[updated_at],
    limit: 750,
    accept: :es_semantic_search_enabled?,
    include: [:repository, { assignments: :assignee }, :labels],
    # When 'delete_documents_from_es: true', repair job can scan with the range from `1` to `last_id` which would
    # make repair job to scan records that are not scoped by the `conditions` defined above.
    #
    # For POC, we'd like to minimize the impact on runing repair job thus we are disabling the document deletion here.
    # This implies that we will not be able to remove documents that are no longer in source.
    # This is fine as the focus here is to compare search efficiency of semantic vs non-semantic indexing.
    delete_documents_from_es: false
end

# rubocop:enable GitHub/EnforcePackageAppStructure
