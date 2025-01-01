# typed: false
#frozen_string_literal: true

module RepositoryAnalyticsHelper
  module RepositoryClick
    module Target
      CLONE_OR_DOWNLOAD_BUTTON = :CLONE_OR_DOWNLOAD_BUTTON
      DISMISS_BANNER = :DISMISS_BANNER
      EVENT_TARGET_UNKNOWN = :EVENT_TARGET_UNKNOWN
      FIND_FILE_BUTTON = :FIND_FILE_BUTTON
      FORK_BUTTON = :FORK_BUTTON
      NEW_PULL_REQUEST_BUTTON = :NEW_PULL_REQUEST_BUTTON
      READ_GUIDE = :READ_GUIDE
      STAR_BUTTON = :STAR_BUTTON
      UNSTAR_BUTTON = :UNSTAR_BUTTON
      WATCH_BUTTON = :WATCH_BUTTON
      COPY_RAW_CONTENTS_BUTTON = :COPY_RAW_CONTENTS_BUTTON
      REFS_SELECTOR_MENU = :REFS_SELECTOR_MENU
      REFS_SELECTOR_MENU_CREATE_BRANCH = :REFS_SELECTOR_MENU_CREATE_BRANCH
    end
  end

  module RepositoryCreateClick
    module Target
      EVENT_TARGET_UNKNOWN = :EVENT_TARGET_UNKNOWN
      IMPORT_REPOSITORY_LINK = :IMPORT_REPOSITORY_LINK
    end
  end

  module RepositoryEmptyStateClick
    module Target
      SET_UP_IN_DESKTOP                = :SET_UP_IN_DESKTOP
      COPY_URL_HTTP                    = :COPY_URL_HTTP
      COPY_URL_SSH                     = :COPY_URL_SSH
      COPY_URL                         = :COPY_URL
      CREATING_NEW_FILE                = :CREATING_NEW_FILE
      UPLOADING_EXISTING_FILE          = :UPLOADING_EXISTING_FILE
      README                           = :README
      LICENSE                          = :LICENSE
      GITIGNORE                        = :GITIGNORE
      COPY_COMMANDS_FOR_CREATING_REPO  = :COPY_COMMANDS_FOR_CREATING_REPO
      COPY_COMMANDS_FOR_UPLOADING_REPO = :COPY_COMMANDS_FOR_UPLOADING_REPO
      IMPORT_CODE                      = :IMPORT_CODE
      ADD_TEAMS_AND_COLLABORATORS      = :ADD_TEAMS_AND_COLLABORATORS
    end
  end

  def watch_button_attributes(repository_id, controller_action_slug)
    hydro_click_tracking_attributes("repository.click",
      target: RepositoryClick::Target::WATCH_BUTTON,
      repository_id: repository_id,
    ).merge(
      "ga-click" => "Repository, click Watch settings, action:#{controller_action_slug}",
    )
  end

  def find_file_data_attributes(repository)
    hydro_click_tracking_attributes("repository.click",
      target: RepositoryClick::Target::FIND_FILE_BUTTON,
      repository_id: repository.id,
    ).merge(
      "ga-click" => "Repository, find file, location:repo overview",
      :"hotkey" => "t"
    )
  end

  def fork_button_data_attributes(repository, controller_action_slug)
    hydro_click_tracking_attributes("repository.click",
      target: RepositoryClick::Target::FORK_BUTTON,
      repository_id: repository.id,
    ).merge(
      "ga-click" => "Repository, show fork modal, action:#{controller_action_slug}; text:Fork",
    )
  end

  def star_button_data_attributes(repository, controller_action_slug)
    ga_attrs = {
      "ga-click" => "Repository, click star button, action:#{controller_action_slug}; text:Star",
    }
    if repository
      hydro_click_tracking_attributes("repository.click",
        target: RepositoryClick::Target::STAR_BUTTON,
        repository_id: repository.id,
      ).merge(ga_attrs)
    else
      ga_attrs
    end
  end

  def unstar_button_data_attributes(repository, controller_action_slug)
    ga_attrs = {
      "ga-click" => "Repository, click unstar button, action:#{controller_action_slug}; text:Unstar",
    }
    if repository
      hydro_click_tracking_attributes("repository.click",
        target: RepositoryClick::Target::UNSTAR_BUTTON,
        repository_id: repository.id,
      ).merge(ga_attrs)
    else
      ga_attrs
    end
  end

  def copy_repository_url_data_attributes(git_repo)
    clone_download_click_attributes(
      git_repo: git_repo,
      feature_clicked: RepositoriesHelper::CloneDownloadClick::FeatureClicked::COPY_URL,
    )
  end

  def clone_or_download_data_attributes(repository)
    hydro_click_tracking_attributes("repository.click",
      repository_id: repository.id,
      target: RepositoryClick::Target::CLONE_OR_DOWNLOAD_BUTTON,
    )
  end

  def download_zip_button_data_attributes(git_repo, ga_click:)
    clone_download_click_attributes(
      git_repo: git_repo,
      feature_clicked: RepositoriesHelper::CloneDownloadClick::FeatureClicked::DOWNLOAD_ZIP,
    ).merge("ga-click" => ga_click)
  end

  def copy_raw_contents_button_attributes(repository)
    hydro_click_tracking_attributes("repository.click",
      target: RepositoryClick::Target::COPY_RAW_CONTENTS_BUTTON,
      repository_id: repository.id,
    )
  end

  def repository_import_link_data_attributes
    hydro_click_tracking_attributes("repository_create.click",
      event_target: RepositoryCreateClick::Target::IMPORT_REPOSITORY_LINK,
    ).merge(
      "ga-click": "Create Repository, import repository, location:repo new",
    )
  end

  def repo_empty_state_click_attributes(repository, event_target)
    event_targets = {
      set_up_in_desktop: RepositoryEmptyStateClick::Target::SET_UP_IN_DESKTOP,
      copy_url_http: RepositoryEmptyStateClick::Target::COPY_URL_HTTP,
      copy_url_https: RepositoryEmptyStateClick::Target::COPY_URL_HTTP,
      copy_url_ssh: RepositoryEmptyStateClick::Target::COPY_URL_SSH,
      copy_url: RepositoryEmptyStateClick::Target::COPY_URL,
      creating_new_file: RepositoryEmptyStateClick::Target::CREATING_NEW_FILE,
      uploading_existing_file: RepositoryEmptyStateClick::Target::UPLOADING_EXISTING_FILE,
      readme: RepositoryEmptyStateClick::Target::README,
      license: RepositoryEmptyStateClick::Target::LICENSE,
      gitignore: RepositoryEmptyStateClick::Target::GITIGNORE,
      copy_commands_for_creating_repo: RepositoryEmptyStateClick::Target::COPY_COMMANDS_FOR_CREATING_REPO,
      copy_commands_for_uploading_repo: RepositoryEmptyStateClick::Target::COPY_COMMANDS_FOR_UPLOADING_REPO,
      import_code: RepositoryEmptyStateClick::Target::IMPORT_CODE,
      add_teams_and_collaborators: RepositoryEmptyStateClick::Target::ADD_TEAMS_AND_COLLABORATORS,
    }

    hydro_click_tracking_attributes("repository_empty_state.click",
      event_target: event_targets[event_target],
      repository_context: repository.in_organization? ? :ORG : :USER,
    )
  end

  def refs_selector_menu_open_attributes(repository)
    hydro_attrs = hydro_click_tracking_attributes("repository.click",
      target: RepositoryClick::Target::REFS_SELECTOR_MENU,
      repository_id: repository.id,
    )

    {
      hydro_click_payload: hydro_attrs["hydro-click"],
      hydro_click_hmac: hydro_attrs["hydro-click-hmac"],
    }
  end

  def refs_selector_menu_create_branch_attributes(repository)
    hydro_click_tracking_attributes("repository.click", {
      target: RepositoryClick::Target::REFS_SELECTOR_MENU_CREATE_BRANCH,
      repository_id: repository.id,
      ref_name: "{{ refName }}",
    })
  end
end
