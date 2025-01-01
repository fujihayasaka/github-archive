# typed: false
# frozen_string_literal: true

class Blob::EditorView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  attr_reader :blob
  attr_reader :filename, :path, :branch, :cancel_url
  attr_reader :allow_contents_unchanged
  attr_reader :default_filename
  attr_reader :contents
  attr_reader :last_commit
  attr_reader :parent_repo
  attr_reader :forked_repo
  attr_reader :old_filename
  attr_reader :target_branch, :quick_pull, :new_filename
  attr_reader :confirm_unload
  attr_reader :default_codemirror_mode
  attr_reader :flow_file_intention
  attr_reader :issue_template_message
  attr_reader :issue_template_flash_classes
  attr_reader :detected_secrets
  attr_reader :unblock_secret_success

  include WebCommit::PreviewViewMethods

  CODE_OF_CONDUCT_FILENAME_REGEXP = /\A(code.?of.?conduct|coc)(\z|\..)/i
  FLOW_FILENAME_REGEXP = /\A\.github\/.+\.workflow\z/
  FUNDING_FILENAME_REGEXP = /\Afunding\.yml\z/i
  LICENSE_FILENAME_REGEXP = RepositoryLicense::FILENAME_REGEXP

  CODE_EDITOR_HOTKEY_SCOPE_ID = "code-editor"

  # Used to hide Code/Show preview dialog when editing Gists
  def gist?
    false
  end

  def blob_filename
    fn = ((blob && path) ? path.last : filename)
    if fn
      fn.dup.force_encoding("UTF-8").scrub!
    end
  end

  def blob_truncated?
    blob.truncated? unless new_file?
  end

  def blob_language
    blob.language unless new_file?
  end

  def blob_binary?
    blob.binary? unless new_file?
  end

  def editable?
    return true if new_file? || !gist?
    !(blob_binary? || blob_truncated?)
  end

  def show_simple_diff?
    !new_file? && is_rich_file?
  end

  def is_rich_file?
    !filename.blank? && blob && blob.viewable? && GitHub::Markup.can_render?(filename, blob.data)
  end

  # Should we show the full screen link, indent, tab v spaces?
  def show_file_actions?
    !blob_binary? && editable?
  end

  def new_file_codemirror_mode
    helpers.detect_filename_language(filename).presence if new_file?
  end

  def language_from_filename
    languages = Linguist::Language.find_by_extension(filename)

    languages.first.name if languages.any?
  end

  def codemirror_mode
    if blob_language
      blob_language.codemirror_mime_type
    elsif new_file_codemirror_mode
      new_file_codemirror_mode
    elsif default_codemirror_mode
      default_codemirror_mode
    else
      ""
    end
  end

  def blob_contents
    new_file? ? contents : (contents || blob.data)
  end

  # Determines if the file being edited is an issue template
  # If the file is an issue template, a contextual message is set
  def issue_template?
    return false unless blob&.repository && blob&.name && blob&.data

    @issue_template_flash_classes = "flash"

    legacy_template = IssueTemplates.valid_legacy_template_path?(blob.path)
    if legacy_template
      @issue_template_message = "You are using an old version of issue templates. Please update to the new issue template workflow."
      @issue_template_flash_classes += " flash-warn"
    end

    multiple_template = IssueTemplates.valid_path?(blob.path)
    if multiple_template
      @issue_template_message = "Looks like this file is an issue template. Need help?"
    end

    multiple_template || legacy_template
  end

  def discussion_template?
    return false unless blob
    return false unless DiscussionTemplates.valid_path?(blob.path)

    blob.repository.discussion_templates[blob.path].present?
  end

  def issue_form?
    IssueTemplate.new(repository: blob&.repository, filename: blob&.name)&.structured?
  end

  def issue_template_banner
    [{
      text: GitHub::HTMLSafeString::EMPTY,
      documentation: true,
      variant: "default",
      file_path: "^(\.github\/ISSUE_TEMPLATE\/(?!config).+\.(md|yaml|yml)$)"
    }]
  end

  def issue_template_help_url
    if issue_form?
      "#{GitHub.help_url}/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository#creating-issue-forms"
    else
      "#{GitHub.help_url}/articles/about-issue-and-pull-request-templates"
    end
  end

  def action
    return attributes[:action] if attributes[:action].present?
    new_file? ? "new" : "edit"
  end

  def default_tab
    "show-code"
  end

  def show_gitignore_picker_on_load?
    @filename == ".gitignore"
  end

  def show_license_picker_on_load?
    return false unless license_picker_available?
    @filename =~ LICENSE_FILENAME_REGEXP
  end

  def show_code_of_conduct_picker_on_load?
    return false unless code_of_conduct_picker_available?
    @filename =~ CODE_OF_CONDUCT_FILENAME_REGEXP
  end

  def code_of_conduct_picker_available?
    GitHub.community_profile_enabled? && parent_repo.pushable_by?(current_user)
  end

  def show_funding_template_callout_on_load?
    return false unless funding_file_callout_enabled?
    @filename =~ FUNDING_FILENAME_REGEXP
  end

  def funding_file_callout_enabled?
    GitHub.sponsors_enabled? && action != "delete"
  end

  def license_picker_available?
    parent_repo.pushable_by?(current_user)
  end

  def profile_readme_callout_enabled?
    return false unless parent_repo.owner == current_user
    parent_repo.user_configuration_repository?
  end

  def show_profile_readme_callout_on_load?
    return false unless profile_readme_callout_enabled?
    @filename == "README.md"
  end

  def org_profile_readme_callout_enabled?
    parent_repo.is_org_profile_repository?
  end

  def show_org_profile_readme_callout_on_load?
    return false unless org_profile_readme_callout_enabled?
    @path == ["profile", "README.md"]
  end

  def org_member_profile_readme_callout_enabled?
    parent_repo.is_org_member_profile_repository?
  end

  def show_org_member_profile_readme_callout_on_load?
    return false unless org_member_profile_readme_callout_enabled?
    @path == ["profile", "README.md"]
  end

  # List of license file options available for init'ing a repository.
  def licenses
    License.sorted_list
  end

  # Public: Returns the proposed path for blob edit / creation.
  #
  # This ensures we can retain the path for things like validation errors where
  # we have to re-render the form with all the values the user is trying.
  #
  # Returns a struct with #to_a and #to_s methods
  def proposed_path
    @proposed_path ||= if new_filename.blank?
      ProposedPath.new(path, File.join(path))
    else
      ProposedPath.new(new_filename.split(File::SEPARATOR), new_filename)
    end
  end

  # Public: The textarea name that stores the blob contents
  def textarea_name
    "value"
  end

  # Public: How many rows should the editor textarea have?
  def textarea_rows
    35
  end

  # Public: whether the last item in the breadcrumb is to be linked
  def linkify_last
    new_file? && filename.blank?
  end

  #Public: Whether to hide the filename
  def hide_filename
    !linkify_last
  end

  def filename_for_display
    filename.dup.force_encoding("UTF-8").scrub!
  end

  def asset_types
    [:assets, :"repository-files"]
  end

  ProposedPath = Struct.new(:to_a, :to_s) do
    def for_display
      to_s.dup.force_encoding("UTF-8").scrub!
    end
  end
end
