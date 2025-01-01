# typed: true
# frozen_string_literal: true

class IntegrationInstallation::SingleFile
  def initialize(repository:, path:)
    @repository = repository
    @path = path
  end

  # Public: read access control on a specific file
  #
  # actor: - The User to check permission for
  def readable_by?(actor)
    permit?(actor, :read)
  end

  def async_readable_by?(actor)
    async_permit?(actor, :read)
  end

  # Public: write access control on a specific file
  #
  # actor: - The User to check permission for
  def writable_by?(actor)
    permit?(actor, :write)
  end

  def async_writable_by?(actor)
    async_permit?(actor, :write)
  end

  private

  # Internal: access control on a specific file
  #
  # actor: - The User to check permission for.
  # action - The Symbol action representing the level of permission to check for.
  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  # TODO: Fix this to work with PATv2 UserProgrammaticAccessGrant actors.
  #
  # https://github.com/github/ecosystem-apps/issues/1657
  def async_permit?(actor, action)
    @repository.resources.contents.async_permit?(actor, action).then do |result|
      if result
        true
      elsif actor.respond_to?(:integration) && single_file_paths(actor).include?(@path)
        Permissions::Service.async_can?(actor, action, @repository.resources.single_file).then do |rezult|
          if rezult
            true
          else
            association_default = @repository.owner.repository_resources.single_file
            association_default.async_permit?(actor, action)
          end
        end
      else
        false
      end
    end
  end

  def single_file_paths(actor)
    # If actor isn't an installation or a Bot, it does
    # not respond to single_file_paths.
    return [] unless actor.respond_to?(:integration)

    # This actor is an installation, if that is the case
    # call `single_file_paths` on the actor directly.
    unless actor.respond_to?(:installation)
      return actor.single_file_paths
    end

    # If for some reason there is a `Bot` without
    # and installation, there isn't a single_file_name
    # to be returned. Make sure that we log it so that we
    # can keep an eye on this.
    if actor.installation.nil?
      GitHub.dogstats.increment("integration.single_file_name", tags: ["missing:installation"])
      return []
    end

    actor.installation.single_file_paths
  end
end
