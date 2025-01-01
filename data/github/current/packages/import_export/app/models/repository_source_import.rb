# typed: true
# frozen_string_literal: true

class RepositorySourceImport
  # Public: Called by RepositorySourceImport.new when instantiating new instance.
  #
  # repository - (required) Instance of Repository.
  # user - (required) Instance of User.
  def initialize(repository:, user:)
    @repository = repository
    @user = user
  end

  # Public: Instance of Repository this import is for.
  #
  # Returns a Repository.
  attr_reader :repository

  # Public: Instance of User that is the actor for this import.
  #
  # Returns a User.
  attr_reader :user

  # Public: Update the importer with the provided auth credentials.
  #
  # vcs_username - (required) String username for source repository.
  # vcs_password - (required) String password for source repository.
  #
  # Returns a Hash of import status info.
  def provide_auth(vcs_username:, vcs_password:)
    self.import_status_hash = porter_client.update_import({
      vcs_username: vcs_username,
      vcs_password: vcs_password,
    })
  end

  # Public: Update the importer with project choice (vcs and project name).
  #
  # project - The Project (from #projects) that was picked.
  #
  # Returns a Hash of import status info.
  def choose_project(project)
    self.import_status_hash = porter_client.update_import(project.for_update)
  end

  # Public: Start an import for the remote repository identified by vcs_url.
  #
  # vcs_url - (required) String url.
  #
  # Returns a Hash of import status info.
  def start_import(vcs_url:)
    GitHub.dogstats.increment("repository.import", tags: ["status:started"])

    # disables actions on the target repo so they will not run automatically after import
    # https://github.com/github/git-import/issues/237
    repository.disable_actions(actor: user)
    self.import_status_hash = porter_client.start_import(vcs_url: vcs_url)

    ImportExport.domain.importing_started!(repository)

    import_status_hash
  end

  # Public: Stop and remove the current importer for this repository.
  def stop_import
    GitHub.dogstats.increment("repository.import", tags: ["status:stopped"])
    porter_client.stop_import
    ImportExport.domain.importing_stopped!(repository)
  end

  # Public: Restart the import.
  #
  # Returns a Hash of import status info.
  def restart_import
    GitHub.dogstats.increment("repository.import", tags: ["status:restarted"])
    self.import_status_hash = porter_client.update_import
  end

  # Public: Opt-in to Git LFS for the import
  def lfs_opt_in(data)
    porter_client.set_lfs_preference(data.merge("use_lfs" => "opt_in"))
  end

  # Public: Opt-out of GIt LFS for the import
  def lfs_opt_out(data)
    porter_client.set_lfs_preference(data.merge("use_lfs" => "opt_out"))
  end

  # Public: The status of the importer.
  #
  # Possible statuses:
  #
  # * :detecting
  # * :auth
  # * :auth_failed
  # * :choose
  # * :importing
  # * :mapping
  # * :pushing
  # * :complete
  # * :error
  #
  # Returns a Symbol.
  def status
    import_status_hash["status"].try(:to_sym)
  end

  # Public: Check if the importer is in specific state.
  #
  # *statuses - Args in Symbol form representing each state to compare against.
  #
  # Example:
  #
  #  > status?(:auth, :auth_failed)
  # => true
  #  > status?(:complete)
  # => false
  #
  # Returns true or false.
  def status?(*statuses)
    statuses.include?(status)
  end

  # Public: Authors found during the import.
  #
  # Returns an Array of Author instances.
  def authors
    @authors ||= begin
      if import_status_hash.has_key?("authors_found")
        porter_client.authors(since: 0)
      else
        []
      end.map { |author_attrs| Author.new(author_attrs) }
    end
  end

  # Public: Update the name, email, and login of a specific author.
  #
  # author_id - (required) Integer id of the author in the importer.
  # name - String human name for author.
  # email - String email address for author.
  # login - String github user login for author.
  #
  # Returns an Author.
  def update_author(author_id:, name: nil, email: nil, login: nil)
    response = porter_client.update_author(author_id, {
      name: name,
      email: email,
      github_user: login,
    })
    Author.new(response)
  end

  # Public: Author class that wraps author details from the importer.
  class Author
    def initialize(options = {})
      @id = options["id"]
      @remote_id = options["remote_id"]
      @remote_name = options["remote_name"]
      @email = options["email"]
      @name = options["name"]
      @login = options["github_user"]
    end

    def display_login
      User.to_display_login(@login)
    end

    attr_accessor :id, :remote_id, :remote_name, :email, :name, :login
  end

  # Public: Projects found during the detection step of the import.
  #
  # Returns an Array of Project instances.
  def projects
    @projects ||= begin
      projects_attrs = Array(import_status_hash["project_choices"])
      projects_attrs.map { |project_attrs| Project.new(project_attrs) }
    end
  end

  # Public: Project class that wraps project details from the importer.
  class Project
    def initialize(options = {})
      @options = options
    end

    # The thing to show to humans
    def name
      @options["human_name"] || to_param
    end
    alias :to_s :name

    # A unique ID for this project.
    #
    # This should be the same across all reloads of the project_choices list.
    # Porter is consistent about how it generates the hash, so this doesn't
    # worry about the hash being in a different order from one request to
    # the next.
    def to_param
      Digest::SHA256.hexdigest(JSON.dump(@options))
    end

    # The attrs that should be used in the PATCH request that
    # selects this project for import.
    def for_update
      @options
    end
  end

  # Public: Have large files been found in this import?
  #
  # Returns true or false.
  def has_large_files?
    !!import_status_hash["has_large_files"]
  end

  # Public: Large file details for the import.
  #
  # Returns a LargeFileDetails.
  def large_file_details(pagination)
    LargeFileDetails.new(porter_client.large_files(pagination))
  end

  class LargeFileDetails
    def initialize(options = {})
      @large_files_count = options["total_count"]
      @files = options["entries"]
      @large_files_size = options["total_size"]
    end

    attr_reader :large_files_count, :files, :large_files_size
  end

  # Public: The error message to display to the user.
  #
  # Returns a String.
  def error_message
    import_status_hash["error_message"]
  end

  # Public: The failed_step for use in the error view
  #
  # Returns a String.
  def failed_step
    import_status_hash["failed_step"]
  end

  # Public: Push percent complete.
  #
  # Returns an Integer.
  def push_percent
    import_status_hash["push_percent"] || 0
  end

  # Public: Import percent complete.
  #
  # Returns an Integer.
  def import_percent
    import_status_hash["percent"] || 0
  end

  # Public: Does the end user need to opt-in or out of using large file storage?
  #
  # Returns true or false.
  def lfs_opt_needed?
    (status?(:complete) || status?(:pushing)) &&
    has_large_files? &&
    import_status_hash["use_lfs"] == "undecided"
  end

  # Public: Does an importer exist already for this repository?
  #
  # Returns true or false
  def no_importer?
    false if import_status_hash
  rescue Porter::ApiClient::Error => error
    if error.status == 404
      true
    else
      raise error
    end
  end

  # Public: How many authors have been found for this import?
  #
  # Returns an Integer.
  def authors_count
    import_status_hash["authors_found"] || 0
  end

  # Public: Were authors found in this migration?
  #
  # Returns true or false.
  def authors_found?
    authors_count > 0
  end

  # Internal: Import status details.
  #
  # Returns a Hash.
  def import_status_hash
    @import_status_hash ||= porter_client.import_status
  end
  attr_writer :import_status_hash

  # Internal: The Porter API client used for making requests to Porter.
  def porter_client
    @porter_client ||= Porter::ApiClient.new(
      current_user: user,
      current_repository: repository,
      timeout: Rails.env.development? ? 5 : 1,
      set_import_started: false,
      send_import_status: true,
    )
  end
  attr_writer :porter_client # for fake client stuff during development

  # Public: Hash with keys and values that repository_import url helpers need.
  #
  # Returns a Hash.
  def url_params
    {
      repository: repository,
      user_id: repository.owner.login,
    }
  end
end
