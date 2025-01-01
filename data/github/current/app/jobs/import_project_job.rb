# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ImportProjectJob < ApplicationJob
  queue_as :import_project

  discard_on ActiveRecord::RecordNotFound
  retry_on_dirty_exit

  def perform(actor, project, column_imports = [])
    return unless project.writable_by?(actor)

    Failbot.push("gh.actor.id": actor.id, "gh.projects.project.id": project.id)

    begin
      import_columns_and_cards!(actor: actor, project: project, column_imports: column_imports)
    ensure
      with_write do
        project.unlock!
      end
    end
  end

  def import_columns_and_cards!(actor:, project:, column_imports:)
    sort_column_imports = column_imports.sort_by { |import| import[:position] }

    # Handles invalid positions in the column imports hash by using each_with_index which addresses
    # imports without a 0 position or imports with a set of positions that are not sequential.
    # eg. [0,1,3] or [10,1,4] import positions will become [0,1,2]
    sort_column_imports.each_with_index do |column_hash, position|
      repo_nwo_with_issue_numbers = column_hash[:issues].each_with_object({}) do |issues, object|
        repo_nwo = issues[:repository]
        next if repo_nwo.to_s.blank?

        issue_number = issues[:number].to_i

        object[repo_nwo] ||= []
        object[repo_nwo] << issue_number
        object
      end

      user_logins = repo_nwo_with_issue_numbers.keys.map { |nwo| nwo.split("/").first }.uniq
      user_id_by_login = User.where(login: user_logins).pluck(:login, :id).to_h

      repos_with_issues = {}
      repo_nwo_with_issue_numbers.each do |nwo, issue_numbers|
        user_login, repo_name = nwo.to_s.split("/")

        repo = Repository.where(owner_id: user_id_by_login[user_login], name: repo_name).first
        next unless repo && (repo.public? || (project.owner_type == "Repository" ? repo == project.owner : repo.owner == project.owner))

        repos_with_issues[repo] = repo.issues.where(number: issue_numbers)
      end

      project_card_issues, note_card_issues = repos_with_issues.values.flatten.partition do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.repository.owner == project.owner
      end

      Project.throttle_writes do
        column = project.columns.find_by(name: column_hash[:column_name])
        unless column
          column = project.columns.create(name: column_hash[:column_name], position: position)
          GitHub.dogstats.increment("job.import_project.project_column.created")
        end

        next unless column.valid?

        add_issue_cards(actor: actor, column: column, issues: project_card_issues)
        add_note_cards(actor: actor, column: column, issues: note_card_issues)
      end

      cards_imported = project_card_issues.length + note_card_issues.length
      GitHub.dogstats.histogram("projects.import_project.total_card_count", cards_imported)
      GitHub.dogstats.histogram("projects.import_project.note_card_count", note_card_issues.length)
      GitHub.dogstats.histogram("projects.import_project.issue_card_count", project_card_issues.length)
      GitHub.dogstats.histogram("projects.import_project.column_count", column_hash.length)
    end
  end

  def add_issue_cards(actor:, column:, issues:)
    existing_cards = column.issue_cards.pluck(:content_id)
    issues.each do |issue|
      next if existing_cards.include?(issue.id)
      add_card(
        actor: actor,
        column: column,
        params: { content_type: "Issue", content_id: issue.id },
      )
    end
  end

  def add_note_cards(actor:, column:, issues:)
    existing_cards = column.note_cards.pluck(:note)
    issues.each do |issue|
      next if existing_cards.include?(issue.permalink)
      add_card(
        actor: actor,
        column: column,
        params: { content_type: "Note", note: "#{issue.permalink}" },
      )
    end
  end

  def add_card(actor:, column:, params:)
    ProjectCard.create_in_column(
      column,
      creator: actor,
      content_params: params,
    )
    GitHub.dogstats.increment("job.import_project.project_card.created")
  end
end
