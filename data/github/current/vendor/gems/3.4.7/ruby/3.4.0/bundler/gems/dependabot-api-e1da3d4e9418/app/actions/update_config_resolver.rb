# frozen_string_literal: true

class UpdateConfigResolver
  # Fetches a broad set of update configs for a given repo and
  # narrows down the results based on the inputs. This is so we
  # don't run user-provided inputs against the database directly.
  def self.for(repo)
    new(repo.active_update_configs)
  end

  delegate :first, to: :@scope

  # returns update configs that the user configured: version update configs
  def user_defined
    new_scope = @scope.where.not(update_schedule: "never")
    self.class.new(new_scope)
  end

  # returns update configs that are ephemeral: security update configs
  def ephemeral
    new_scope = @scope.where(update_schedule: "never")
    self.class.new(new_scope)
  end

  def with_package_manager(package_manager)
    raise ArgumentError, "package_manager cannot be nil" if package_manager.nil?

    new_scope = @scope.where(package_manager: package_manager)
    self.class.new(new_scope)
  end

  def with_target_branch(target_branch)
    # subtle: nil is a valid target_branch
    new_scope = @scope.where(target_branch: target_branch)
    self.class.new(new_scope)
  end

  def with_directory(directory)
    raise ArgumentError, "directory cannot be nil" if directory.nil?

    new_scope = @scope.select do |config|
      # use cover, because we KNOW the directory is not a glob, even if it looks like one
      config.manifest_directories.cover?(directory)
    end

    self.class.new(new_scope)
  end

  private

  def initialize(scope)
    @scope = scope
  end
end
