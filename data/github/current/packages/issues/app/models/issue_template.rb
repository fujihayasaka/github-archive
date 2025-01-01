# typed: true
# frozen_string_literal: true

class IssueTemplate
  include ActiveModel::Validations

  attr_writer :other_templates

  YAML_FILES = /\A\.(yaml|yml)\z/
  MD_FILES = /\A\.md\z/

  validates :name, presence: true, length: { maximum: 200, minimum: 3, allow_blank: true }
  validate :name_uniqueness
  validate :about_or_description_present
  validate :issue_form_template_errors

  def self.default(name, repository: nil)
    case name
    when :bug
      new(repository: repository, filename: "bug_report.md",
        name: "Bug report",
        about: "Create a report to help us improve",
        title: "",
        labels_string: "",
        assignees_string: "",
        body: <<~MARKDOWN
        **Describe the bug**
        A clear and concise description of what the bug is.

        **To Reproduce**
        Steps to reproduce the behavior:
        1. Go to '...'
        2. Click on '....'
        3. Scroll down to '....'
        4. See error

        **Expected behavior**
        A clear and concise description of what you expected to happen.

        **Screenshots**
        If applicable, add screenshots to help explain your problem.

        **Desktop (please complete the following information):**
         - OS: [e.g. iOS]
         - Browser [e.g. chrome, safari]
         - Version [e.g. 22]

        **Smartphone (please complete the following information):**
         - Device: [e.g. iPhone6]
         - OS: [e.g. iOS8.1]
         - Browser [e.g. stock browser, safari]
         - Version [e.g. 22]

        **Additional context**
        Add any other context about the problem here.
        MARKDOWN
      )
    when :feature
      new(repository: repository, filename: "feature_request.md",
        name: "Feature request",
        about: "Suggest an idea for this project",
        title: "",
        labels_string: "",
        assignees_string: "",
        body: <<~MARKDOWN
        **Is your feature request related to a problem? Please describe.**
        A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

        **Describe the solution you'd like**
        A clear and concise description of what you want to happen.

        **Describe alternatives you've considered**
        A clear and concise description of any alternative solutions or features you've considered.

        **Additional context**
        Add any other context or screenshots about the feature request here.
        MARKDOWN
      )
    when :blank
      new(repository: repository, filename: "custom.md",
        name: "Custom issue template",
        about: "Describe this issue template's purpose here.",
        title: "",
        labels_string: "",
        assignees_string: "",
      )
    end
  end

  def self.preview(repository, filename, hashes)
    template = from_hash(repository, hashes[filename])
    template.other_templates = hashes.values.map { |v| from_hash(repository, v) }
    template
  end

  def self.from_hash(repository, hash)
    labels = stringify_if_array(hash["labels"])
    assignees = stringify_if_array(hash["assignees"])
    projects = stringify_if_array(hash["projects"])

    new(
      repository: repository,
      filename: hash["filename"],
      name: hash["name"],
      about: hash["about"],
      title: hash["title"],
      type: hash["type"],
      body: hash["body"],
      labels_string: labels,
      assignees_string: assignees,
      projects_string: projects,
    )
  end

  def self.from_tree_entry(tree_entry, viewer = nil)
    use_structured_templates = File.extname(tree_entry.name) =~ YAML_FILES
    if use_structured_templates
      config = IssueForms::TemplateConfig.new(input: tree_entry.data, path: tree_entry.path, type_field_enabled: tree_entry.repository.issue_forms_type_field_enabled?(viewer))
      config.required_fields_enabled = tree_entry.repository.issue_forms_required_fields_enabled?
      config = config.load

      new_from_structured_template_config(
        config: config,
        repository: tree_entry.repository,
        filename: tree_entry.name,
      )
    else
      new_from_markdown(tree_entry.repository, tree_entry.name, tree_entry.data)
    end
  end

  def self.new_from_markdown(repository, filename, markdown)
    front_matter = FrontMatter.new(markdown)
    config = FrontMatter.new(markdown).parsed_yaml

    if config.nil?
      return
    end

    new_from_config(config, front_matter.body, repository, filename)
  end

  def self.new_from_config(config, body, repository, filename)
    config = !config.is_a?(Hash) ? {} : config
    labels = stringify_if_array(config["labels"])
    assignees = stringify_if_array(config["assignees"])

    new(
      repository: repository,
      filename: filename,
      name: config["name"],
      about: config["about"],
      title: config["title"],
      body: body,
      labels_string: labels,
      assignees_string: assignees,
      type: config["type"]
    )
  end

  def self.new_from_structured_template_config(config:, repository:, filename:)
    labels = stringify_if_array(config.labels)
    assignees = stringify_if_array(config.assignees)
    projects = stringify_if_array(config.projects)

    template = new(
      repository: repository,
      filename: filename,
      name: config.name,
      inputs: config.body,
      user_inputs: config.user_inputs,
      about: config.description,
      title: config.title,
      labels_string: labels,
      assignees_string: assignees,
      projects_string: projects,
      include_body: false,
      type: config.type
    )
    template.config_errors = config.errors if config.errors.any?
    template
  end

  attr_reader :repository, :name, :about, :body, :labels_string, :projects_string, :assignees_string, :title, :inputs, :user_inputs, :include_body, :user, :type
  attr_accessor :config_errors
  alias_method :include_body?, :include_body

  def initialize(
    repository:,
    filename: "",
    name: "",
    about: "",
    body: "",
    other_templates: nil,
    labels_string: "",
    assignees_string: "",
    projects_string: "",
    title: "",
    inputs: nil,
    user_inputs: nil,
    include_body: true,
    user: nil,
    type: ""
  )
    @repository = repository
    @filename = filename
    @name = name
    @about = about
    @body = body
    @labels_string = labels_string.to_s
    @assignees_string = assignees_string.to_s
    @projects_string = projects_string.to_s
    @other_templates = other_templates
    @title = title
    @inputs = inputs || []
    @user_inputs = user_inputs || []
    @include_body = include_body
    @user = user
    @type = type
  end

  def is_yaml_file?
    return unless @filename
    ext = File.extname(@filename)
    !!(ext =~ YAML_FILES)
  end

  def is_md_file?
    ext = File.extname(@filename)
    !!(ext =~ MD_FILES)
  end

  def structured?
    is_yaml_file?
  end

  def legacy_template_supported?
    is_md_file?
  end

  def issue_forms_supported?
    is_yaml_file? || is_md_file?
  end

  def supported?(repo)
    issue_forms_supported?
  end

  def async_repository
    Promise.resolve(repository)
  end

  def filename
    @filename.presence || name.gsub(/[^\p{Letter}\p{Mark}\p{Number}\p{Connector_Punctuation}\p{Emoji}]/, "-") + ".md"
  end

  def filename_for_display
    filename.dup.force_encoding("UTF-8").scrub!
  end

  def issue
    @issue ||= repository.issues.new.tap do |new_issue|
      new_issue.labels = labels
      new_issue.assignees = assignees
      new_issue.memex_projects = projects
    end
  end

  def assignees
    @assignees ||= prefilled_issue_fields.assignees
  end

  def labels
    @labels ||= prefilled_issue_fields.labels
  end

  def projects
    @projects ||= prefilled_issue_fields.memex_projects
  end

  def projects_for_viewer(viewer)
    @projects_for_viewer ||= Hash.new
    return @projects_for_viewer[viewer] if @projects_for_viewer[viewer].present?
    @projects_for_viewer[viewer] = prefilled_issue_fields.memex_projects_for_viewer(viewer)
  end

  def to_markdown
    front_matter = YAML.dump(front_matter_hash)
    [front_matter, "---", "", @body.to_s.strip, ""].join("\n")
  end

  def parameterized_name
    @name&.parameterize(separator: "_")
  end

  def uses?(field_name)
    used_front_matter_fields.include?(field_name.to_s)
  end

  def project_count
    @projects_string.split(",").length
  end

  def track_required_inputs(action:)
    return unless structured?
    return if user_inputs.empty?

    GitHub.dogstats.increment("issues.with_template", tags: [
      "action:#{action}",
      "owner_type:#{repository.owner.type}",
      "repo_visibility:#{repository.private? ? "private" : "public"}",
      "required_fields:#{required_field_threshold}"
    ])
  end

  private

  def used_front_matter_fields
    used_fields = front_matter_hash
    if structured? && !@projects_string.empty?
      used_fields.merge!({ "projects" => @projects_string })
    end

    used_fields.delete_if { |_, value| value.blank? }.keys
  end

  def front_matter_hash
    hash = {
      "name" => @name,
      "about" => @about,
      "title" => @title,
      "labels" => @labels_string,
      "assignees" => @assignees_string,
    }

    hash
  end

  def prefilled_issue_fields
    @prefilled_issue_fields ||= PrefilledIssueFields.new(
      params: { assignees: assignees_string, labels: labels_string, projects: projects_string, type: type },
      repository: repository,
      user: user,
    )
  end

  def other_templates
    @other_templates || repository.issue_templates.templates
  end

  def name_uniqueness
    return unless other_templates

    clashes = other_templates.any? do |template|
      if template.name == name
        next if converting_to_issue_form?(template.filename, filename)
        template.filename != filename
      end
    end
    errors.add(:name, "must be unique") if clashes
  end

  def about_or_description_present
    field_name = File.extname(filename) =~ YAML_FILES ? :description : :about

    if !about.present?
      errors.add(field_name, "can't be blank")
      return
    end

    length = about.is_a?(String) ? about.size : about.to_s.size
    errors.add(field_name, "must be between 3 and 200 characters") if length < 3 || length > 200
  end

  def converting_to_issue_form?(existing_path, new_path)
    return unless structured?
    existing_path == new_path.sub(/\.yaml|\.yml/, ".md")
  end

  # If this is a issue form template error, composition errors from IssueForms::TemplateConfig
  # should supercede IssueTemplate validations
  def issue_form_template_errors
    return unless config_errors
    errors.clear
    errors.merge!(config_errors)
  end

  def self.stringify_if_array(items)
    items.respond_to?(:join) ? items.join(",") : items
  end
  private_class_method :stringify_if_array

  def required_field_threshold
    num_inputs = user_inputs.count
    num_required_inputs = user_inputs.count(&:required)
    percentage = (num_required_inputs / num_inputs.to_f) * 100

    if percentage == 0
      "0"
    elsif percentage > 0 && percentage <= 50
      "1-50"
    elsif percentage > 50 && percentage <= 75
      "51-75"
    else
      "76-100"
    end
  end
end
