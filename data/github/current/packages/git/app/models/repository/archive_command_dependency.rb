# typed: true
# frozen_string_literal: true

module Repository::ArchiveCommandDependency
  LEGACY_REGEX = /\Alegacy\./

  # Creates an instance of ArchiveCommand with this git repo instance.
  # See GitRepository::ArchiveCommand#initialize.
  #
  # Returns an GitRepository::ArchiveCommand instance.
  def archive_command(commitish, type, actor_id: nil, actor_token: nil)
    type = type.to_s

    if type.match(LEGACY_REGEX)
      GitRepository::LegacyArchiveCommand.new self, commitish, type.gsub(LEGACY_REGEX, ""), actor_id: actor_id, actor_token: actor_token
    else
      GitRepository::ArchiveCommand.new self, commitish, type, actor_id: actor_id, actor_token: actor_token
    end
  end
end
