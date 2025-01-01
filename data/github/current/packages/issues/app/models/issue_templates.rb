# typed: true
# frozen_string_literal: true

class IssueTemplates
  class UpdateResult
    attr_reader :error, :pull_request, :hook_output

    def initialize(ok, error, pull_request, hook_output = nil)
      @ok, @error, @pull_request, @hook_output = ok, error, pull_request, hook_output
    end

    def ok?
      @ok
    end
  end

  attr_reader :repository, :viewer

  LEGACY_TEMPLATE_PATH_REGEX = /\A(\.github\/)?issue(_|-)template\.md\z/i
  TEMPLATE_CONFIG_PATH_REGEX = /\Aconfig\.(yaml|yml)\z/i
  TEMPLATE_CONFIG_PATH_STRICT_REGEX = /\Aconfig.yml\z/i

  def self.valid_path?(string, repository = nil)
    return false unless string.starts_with?(template_directory)

    File.extname(string) =~ /\A\.(md|yml|yaml)\z/i && File.basename(string) !~ TEMPLATE_CONFIG_PATH_REGEX
  end

  def self.valid_legacy_template_path?(path_string)
    LEGACY_TEMPLATE_PATH_REGEX.match?(path_string)
  end

  def self.valid_yaml_template_path?(path_string, repository)
    valid_path?(path_string, repository) && path_string.end_with?(".yml", ".yaml")
  end

  def self.template_directory
    ".github/ISSUE_TEMPLATE"
  end

  def initialize(repository, viewer = nil, filter = nil)
    @repository = repository
    @viewer = viewer
    @filter = filter
  end

  def update(templates, branch:, updater:, commit_title:, commit_body:, reflog_data:, remove_issue_forms: true)
    branch = Git::Ref.normalize(branch)
    commit_oid = repository.ref_to_sha(repository.default_branch)
    qualified_ref_name = "refs/heads/#{branch}"
    ref = repository.heads[qualified_ref_name]
    is_creating_pr = false

    commit_message = [commit_title, commit_body].reject(&:blank?).join("\n\n")
    commit = repository.commits.create({ message: commit_message, author: updater }, commit_oid, sign: true, target_ref_name: qualified_ref_name) do |files|
      templates_by_filename.each do |filename, template|
        files.remove File.join(IssueTemplates.template_directory, filename) unless !remove_issue_forms && template.structured?
      end
      templates.each do |hash|
        hash.each do |filename, body|
          files.add File.join(IssueTemplates.template_directory, filename), body.gsub(/\r\n/, "\n")
        end
      end
    end

    if commit.diff.empty?
      return UpdateResult.new(false, "The commit cannot be empty", nil, nil)
    end

    if ref.nil?
      begin
        ref = repository.refs.create(qualified_ref_name,
                                     commit_oid.presence || commit.oid,
                                     updater,
                                     reflog_data: reflog_data,
                                    )
        is_creating_pr = ref.name != repository.default_branch
      rescue Git::Ref::ExistsError
        return UpdateResult.new(false, "That branch already exists", nil, nil)
      rescue Git::Ref::InvalidName, Git::Ref::UpdateFailed
        return UpdateResult.new(false, "That branch name is invalid", nil, nil)
      rescue Git::Ref::HookFailed => e
        return UpdateResult.new(false, "That branch could not be created.", nil, e.message)
      end
    end

    begin
      ref.update(commit, updater, reflog_data: reflog_data)

      if is_creating_pr
        pull_request = PullRequest.create_for(repository, {
          base: repository.default_branch,
          head: branch,
          title: commit_title,
          body: commit_body,
          user: updater,
        })

        unless pull_request.valid?
          return UpdateResult.new(false, "Pull request could not be created", pull_request, nil)
        end
      end
    rescue Git::Ref::ProtectedBranchUpdateError
      return UpdateResult.new(false, "That branch is protected", nil, nil)
    rescue Git::Ref::RepositoryRuleViolationError => e
      return UpdateResult.new(false, e.message, nil, e.detailed_message)
    rescue Git::Ref::HookFailed => e
      return UpdateResult.new(false, "Issue Templates could not be created.", nil, e.message)
    end

    UpdateResult.new(true, nil, pull_request, nil)
  end

  def [](name)
    templates_by_filename.reverse_merge(legacy_templates_by_filename)[name]
  end

  def find_by_name(name) # rubocop:disable GitHub/FindByDef
    templates_with_legacy.find { |template| template.name == name }
  end

  def any?
    valid_templates.any?
  end

  def valid_templates
    @valid_templates ||= templates.select(&:valid?)
  end

  def valid_yaml_templates
    @valid_yaml_templates ||= templates.select(&:structured?).select(&:valid?)
  end

  def templates
    @templates ||= templates_by_filename.values
  end

  def templates_with_legacy
    @templates_with_legacy ||= templates_by_filename.values + legacy_templates_by_filename.values
    @templates_with_legacy.select(&:valid?)
  end

  def legacy_template
    @legacy_template ||= legacy_templates_by_filename.values.first
  end

  def legacy_template?
    legacy_template.present?
  end

  def legacy_template_path
    legacy_template_tree_entries.find { |tree_entry| tree_entry["path"] =~ LEGACY_TEMPLATE_PATH_REGEX }&.path
  end

  def issue_template_config
    @config ||= begin
      entry = template_tree_entries.detect do |tree_entry|
        tree_entry.name =~ TEMPLATE_CONFIG_PATH_STRICT_REGEX
      end
      IssueTemplateConfig.new(repository: repository, data: entry&.data)
    end
  end

  private

  def templates_by_filename
    @templates_by_filename ||= {}
    key = @filter || "no_filter"
    @templates_by_filename[key] ||= template_tree_entries.each_with_object({}) do |tree_entry, result|
      tree_entry_name = tree_entry.name&.dup&.force_encoding("UTF-8")&.scrub!
      next if @filter && @filter != File.basename(tree_entry_name)
      next unless File.extname(tree_entry_name) =~ /\A\.(md|yml|yaml)\z/i
      next if File.basename(tree_entry_name) =~ TEMPLATE_CONFIG_PATH_REGEX

      next unless template = IssueTemplate.from_tree_entry(tree_entry, viewer)

      result[template.filename] = template
    end
  end

  def legacy_templates_by_filename
    @legacy_templates_by_name ||= legacy_template_tree_entries.each_with_object({}) do |tree_entry, result|
      next unless tree_entry.name =~ /\Aissue(_|-)template\.md\z/i
      data = tree_entry.data
      markdown = <<~MARKDOWN
        ---
        name: Default issue template
        about: default issue template
        ---
        #{data}
      MARKDOWN
      template = IssueTemplate.new_from_markdown(tree_entry.repository, tree_entry.name, markdown)
      result[template.filename] = template
    end
  end

  def legacy_directories
    [".github/", "."]
  end

  def template_tree_entries
    if @repository.nil?
      return []
    end

    if @repository.access.broken?
      return []
    end

    begin
      directory = @repository.directory(@repository.default_oid, IssueTemplates.template_directory)
      directory&.tree_entries || []
    rescue GitRPC::Error, Repository::CorruptionDetected
      []
    end
  end

  def legacy_template_tree_entries
    if @repository.nil?
      return []
    end

    if @repository.access.broken?
      return []
    end

    begin
      legacy_directories.map do |legacy_directory|
        directory = @repository.directory(@repository.default_oid, legacy_directory)
        directory&.tree_entries || []
      rescue GitRPC::Error, Repository::CorruptionDetected
        []
      end.flatten
    end
  end
end
