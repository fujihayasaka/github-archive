# typed: true
# frozen_string_literal: true
#
# A class for creating automatically generated release notes for a given release.
# Allows customizing the release notes by passing a configuration file or specific
# previous_tag values.
class Release::ReleaseNotes
  extend T::Sig

  RELEASE_NOTES_CONFIG_PATHS = [".github/release.yml", ".github/release.yaml"].freeze
  RELEASE_NOTES_TEMPLATE = <<~EOS
    ${{config_file_path_comment}}
    ${{changelog}}
    ${{new_contributors}}
    ${{compare}}
  EOS
  .freeze
  # We will treat this as matching all PRs when supplied as a label option
  # to the changelog category config
  RELEASE_NOTES_PR_LABEL_WILDCARD = "*"
  ZERO_PR_MESSAGE = "There were no pull requests associated with the commits included in this release."

  # Params:
  #   previous_tag_name - A previous tag to use as the starting point for changes included
  #     as part of this release. Defaults to a previous semver tag, or the previous release if not defined.
  #   template - A string that specifies a generic layout for Release Notes. Supports variables
  #     defined by ${{variable}} syntax. See create_release_notes_variables for a list of supported variables.
  #     This will default to RELEASE_NOTES_TEMPLATE if the parameter is nil.
  #   configuration_file_path - A path to a YAML file that contains a hash of configuration options.
  sig do
    params(
      release: ::Release,
      previous_tag_name: T.nilable(String),
      template: T.nilable(String),
      configuration_file_path: T.nilable(String),
    ).void
  end
  def initialize(release, previous_tag_name: nil, template: nil, configuration_file_path: nil)
    raise Releases::Error, "Invalid previous_tag parameter" if previous_tag_name.present? && T.must(release.repository).tags.find(previous_tag_name).blank?
    @release = release
    @repo = T.must(release.repository)
    @release_range_start_tag = previous_tag_name if previous_tag_name.present?
    @template = template
    @configuration_file_path = configuration_file_path
  end

  # Method to generate Release Notes for this Release.
  #
  # Returns:
  #   title - The title of the release notes.
  #   body - The body of the release notes.
  #   warning_message - A string describing any warnings that occurred during the generation process, or empty string if no warnings occured
  sig { returns(Releases::IReleaseNotes) }
  def generate
    config_helper = create_release_notes_config_helper
    content_variables_hash = create_release_notes_variables(config_helper)
    title = format_release_notes_content(config_helper.configuration_hash["title"], content_variables_hash)
    body = format_release_notes_content(@template, content_variables_hash)
    instrument_release_notes_generated
    message = prs_merged_since_release_range_start_tag.count == 0 ? ZERO_PR_MESSAGE : ""
    [title, body, message]
  end

  private

  # Defines a tag to use as the starting point for the range of changes that are considered
  # part of this release.
  sig { returns(T.nilable(String)) }
  def release_range_start_tag
    return @release_range_start_tag if defined?(@release_range_start_tag)

    @release_range_start_tag = Release::SearchTags.new(@release).find_previous_version_tag
  end

  # Intialize Release::ReleaseNotesConfigHelper with the repo's config file
  sig { returns(Release::ReleaseNotesConfigHelper) }
  def create_release_notes_config_helper
    file = T.let(nil, T.untyped)
    if @configuration_file_path.present?
      file = load_release_notes_config_file!(@configuration_file_path)
    else
      RELEASE_NOTES_CONFIG_PATHS.each do |path|
        file = load_release_notes_config_file(path)
        break if file.present?
      end
    end
    Release::ReleaseNotesConfigHelper.new(file)
  end

  # Load the repo's release notes configuration file
  # Raises a Releases::Error if the file is not found
  def load_release_notes_config_file!(path)
    file = load_release_notes_config_file(path)
    raise Releases::Error, "Could not find a configuration file at #{path}" if file.nil?
    file
  end

  # Load the repo's release notes configuration file
  def load_release_notes_config_file(path)
    @repo.tree_entry(@repo.ref_to_sha(@release.current_target), path)
  rescue GitRPC::NoSuchPath
    nil
  end

  # Create a hash of content variables and string values used to format a release notes content template.
  sig { params(config_helper: Release::ReleaseNotesConfigHelper).returns(T::Hash[String, String]) }
  def create_release_notes_variables(config_helper)
    content_variables = Hash.new
    content_variables["${{date}}"] = Time.now.in_time_zone.strftime("%Y-%m-%d")
    content_variables["${{version}}"] = @release.exposed_tag_name
    content_variables["${{compare}}"] = generate_release_notes_compare(config_helper.configuration_hash["compare"])
    content_variables["${{changelog}}"] = generate_changelog(config_helper.configuration_hash["changelog"])
    content_variables["${{new_contributors}}"] = generate_new_contributors(config_helper.configuration_hash["new_contributors"])
    content_variables["${{config_file_path_comment}}"] = release_notes_config_comment(config_helper)
    content_variables
  end

  # Create the ${{compare}} section of release notes.
  # If there is a previous semver tag, use that as the comparison base for the new release,
  # otherwise we will use the previous Release,
  # finally we will default to showing the commits view for the default branch.
  def generate_release_notes_compare(config)
    if release_range_start_tag.present?
      diff_url = @repo.comparison(release_range_start_tag, @release.exposed_tag_name).to_url
    elsif @release.previous_release?
      diff_url = @repo.comparison(@release.previous_release.exposed_tag_name, @release.exposed_tag_name).to_url
    else
      diff_url = "#{GitHub.url}#{@repo.async_commits_path_uri(commitish: @release.exposed_tag_name).sync}"
    end

    content = {
      "${{compare_url}}" => diff_url
    }

    format_release_notes_content(config["default_text"], content)
  end

  # Parse the passed in content template, or RELEASE_NOTES_TEMPLATE if nil, for any variables denoted by ${{variable}}.
  # Variables will be replaced using the input content_variables_hash. This hash is generated by create_release_notes_variables.
  #
  # Params:
  #   content - A string that specifies a generic layout for Release Notes. Supports variables
  #     defined by ${{variable}} syntax. See create_release_notes_variables for a list of supported variables.
  #     This will default to RELEASE_NOTES_TEMPLATE if the parameter is nil.
  #   content_variables_hash - A hash of variable names and values generated from create_release_notes_variables.
  #
  # Returns:
  #   A string containing the formatted content template where ${{variable}} has been replaced with the associated value
  def format_release_notes_content(content, content_variables_hash)
    content ||= RELEASE_NOTES_TEMPLATE.dup
    # Find variables in content denoted by ${{non_whitespace_characters}}
    content.gsub(/\$\{\{\S+\}\}/, content_variables_hash).strip
  end

  # Create the ${{changelog}} section of release notes.
  def generate_changelog(config)
    # handle any globally excluded prs
    # add wildcard for this call since root config includes everything by default
    prs_for_changelog = filter_prs_for_category(
      prs_merged_since_release_range_start_tag,
      config.merge({ "labels" => [RELEASE_NOTES_PR_LABEL_WILDCARD] })
    )
    changelog = ""

    if config["categories"].any?
      # If we have categories configured, bucket the PRS into those categories
      remaining_prs_to_categorize = prs_for_changelog
      changelog = config["categories"].map do |category_config|
        labels = category_config["labels"] || []
        title = category_config["title"] || "Pull Requests with labels: " + labels.join(", ")

        # prs in the category are prs which have the right label and are not excluded
        prs_in_category = filter_prs_for_category(remaining_prs_to_categorize, category_config)
        next unless prs_in_category.present?

        remaining_prs_to_categorize = remaining_prs_to_categorize - prs_in_category

        "### #{title}" + "\n" + format_pr_changelog_lines(prs_in_category, config)
      end.compact.join("\n")
    else
      # If there are no categories specified, just put all the PRs in the changelog section
      changelog = format_pr_changelog_lines(prs_for_changelog, config)
    end

    changelog.present? ? "## #{config["header"]}" + "\n" + changelog + "\n" : ""
  end

  # Given an array of PRs and a category config hash, filter the
  # PRs to only those which should be included in the category
  def filter_prs_for_category(pull_requests, category_config)
    exclude_labels = category_config.dig("exclude", "labels") || []
    exclude_authors = category_config.dig("exclude", "authors") || []

    include_labels = category_config["labels"] || []

    pull_requests.select do |pr|
      has_include_label = changelog_pr_has_any_label?(pr, include_labels)
      has_exclude_label = changelog_pr_has_any_label?(pr, exclude_labels)
      has_exclude_author = exclude_authors.include?(pr.user&.name)

      has_include_label && !(has_exclude_author || has_exclude_label)
    end
  end

  # Given a PR and an array of label names which may include RELEASE_NOTES_PR_LABEL_WILDCARD
  # return a boolean for whether the PR has any of the labels
  def changelog_pr_has_any_label?(pull_request, label_names = [])
    return true if label_names.include?(RELEASE_NOTES_PR_LABEL_WILDCARD)

    pull_request.labels.map(&:name).intersection(label_names).any?
  end

  # Retrieve all PRs that have a merge_commit_sha somewhere in this release's commits
  # PRs that are merged, squashed, or rebased will all be found by this method
  def prs_merged_since_release_range_start_tag
    return @prs_since_release_range_start_tag if defined?(@prs_since_release_range_start_tag)
    # commit_oids is limited to COMMITS_LIMIT
    oids = commit_oids_since_release_range_start_tag
    @prs_since_release_range_start_tag = T.must(@repo).pull_requests
      .includes(issue: :labels)
      .where(merge_commit_sha: oids)
      .where.not(merged_at: nil)
      .order(:merged_at, :id).all
  end

  # find commit oids since the previous semver tag
  # if no such tag can be found, defaults to commit_oids
  def commit_oids_since_release_range_start_tag
    if release_range_start_tag
      GitHub::Comparison.from_range(
        @repo,
        "#{release_range_start_tag}...#{@release.current_target}"
      ).rev_list.first(Release::COMMITS_LIMIT)
    else
      @release.commit_oids
    end
  end

  # Given an array of PRs and the changelog config,
  # return a line of formatted text for each PR
  def format_pr_changelog_lines(prs, config)
    prs.map do |pr|
      content = {
        "${{pr_title}}" => pr.title,
        "${{pr_author}}" => "@#{pr.user&.name}",
        "${{pr_url}}" => pr.permalink
      }

      "* " + format_release_notes_content(pr.user.present? ? config["default_text"] : config["no_author_text"], content)
    end.join("\n")
  end

  # Create the ${{new_contributors}} section of release notes.
  def generate_new_contributors(config)
    section_content = new_contributor_prs.map do |pr|
      next unless pr.user.present?
      content = {
        "${{contributor_name}}" => "@#{pr.user.name}",
        "${{contribution}}" => pr.permalink
      }

      "* " + format_release_notes_content(config["default_text"], content)
    end.compact.join("\n")

    section_content.present? ? "## #{config['header']}" + "\n" + section_content + "\n" : ""
  end

  # PRs in the release landed by first time contributors
  def new_contributor_prs
    T.must(@repo).first_time_contributions(prs_merged_since_release_range_start_tag)
  end

  # comment to be added to release notes markdown
  # clarifying where release notes configuration was pulled from
  def release_notes_config_comment(config_helper)
    file_path = config_helper&.release_config_file&.path
    return "" unless file_path.present?

    "<!-- Release notes generated using configuration in #{file_path} at #{@release.current_target} -->\n"
  end

  def instrument_release_notes_generated
    GlobalInstrumenter.instrument("release.notes_generated", {
      release: @release,
      repository: @repo,
      owner: @repo&.owner,
    })
  end
end
