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
      .map { |v| Integer(v.split(":")[1]) }

    org_ids = GitHub
      .flipper[:elasticsearch_semantic_indexing_issues]
      .actors_value
      .to_a
      .select { |v| v.include?("Organization") }
      .map { |v| Integer(v.split(":")[1]) }
    # if org_ids.present?
    #   repo_ids |= org_ids.map { |id| Organization.find_by(id:) }.compact.flat_map { |org| org.repositories.map(&:id) }
    # end

    job.class.reconcilers.first[:conditions] = proc { |_, job|
      if repo_ids.empty? || org_ids.present?
        # Also ignores repository_ids filter if enabling for entire org
        "issues.has_pull_request = 0"
      else
        offset = job.reconcilers&.first&.get_offset
        model_class = job.class.reconcilers.first[:model_class]
        subquery_rel = model_class.where(has_pull_request: 0, repository_id: repo_ids).select(:id)
        if offset.nil?
          "`issues`.`id` IN (#{subquery_rel.to_sql})"
        else
          "`issues`.`id` IN (#{subquery_rel.where("`issues`.`id` > ?", offset).to_sql})"
        end
      end
    }

    block.call
  end

  reconcile "issue_semantic",
    model_class: Issue,
    fields: %w[updated_at],
    limit: 750,
    accept: :es_semantic_search_enabled?,
    reject: :spammy?,
    include: [:repository, { assignments: :assignee }, :labels],
    # When 'delete_documents_from_es: false', repair job only queries ES from the same ids range as MySQL model
    delete_documents_from_es: false
end

# rubocop:enable GitHub/EnforcePackageAppStructure
