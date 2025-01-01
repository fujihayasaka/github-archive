# typed: true
# frozen_string_literal: true

# Sets and unsets search shortchuts for the user
class SearchShortcutsSetter
  def initialize(user)
    @user = user
    @dashboard = user.find_or_create_dashboard
  end

  # Destroy and recreate all shortcuts for a dashboard with descending
  # priority values based on the order of the shortcuts passed in.
  # Does not run validation, validation is expected to have occurred before
  # calling this method.
  #
  # shortcuts - An Array of shortcut inputs.
  #
  # Returns nothing.
  def set(shortcuts)
    errors = validate_shortcuts(shortcuts)

    return Result.failure(errors: errors) if errors.any?

    now = Time.current.to_formatted_s(:db)

    shortcut_row_promises = shortcuts.zip(shortcuts.size.downto(1)).map do |shortcut_hash, priority_mult|
      nwo = fetch_repo_nwo(shortcut_hash)
      async_scoping_repo(nwo).then do |scoping_repo|
        {
          dashboard_id: dashboard.id,
          priority: priority_mult * GitHub::Prioritizable::GAP_SIZE + GitHub::Prioritizable::START_VALUE,
          name: shortcut_hash[:name],
          search_type: shortcut_hash[:search_type],
          icon: shortcut_hash[:icon],
          color: shortcut_hash[:color],
          compressed_query: shortcut_hash[:query].to_s,
          scoping_repository_id: scoping_repo&.id,
          created_at: now,
          updated_at: now,
        }
      end
    end

    # Will raise a NotFound exception if any scoping repositories are inaccessible.
    shortcut_rows = Promise.all(shortcut_row_promises).sync

    existing_shortcuts = ::SearchShortcut.where(dashboard_id: dashboard.id)
    existing_shortcuts_a = existing_shortcuts.to_a

    ::SearchShortcut.transaction do
      existing_shortcuts.delete_all
      ::SearchShortcut.insert_all!(shortcut_rows) if shortcut_rows.present?
    end

    existing_shortcuts_a.each do |shortcut|
      SearchShortcut.instrument_destroy(
        search_type: shortcut.search_type,
        scoping_repository_id: shortcut.scoping_repository_id,
        user: user,
        context: "mobile",
      )
    end

    shortcut_rows.each do |row|
      SearchShortcut.instrument_create(
        search_type: row[:search_type],
        user: user,
        scoping_repository_id: row[:scoping_repository_id],
        context: "mobile",
      )
    end

    Result.success
  end

  private

  attr_reader :user, :dashboard

  def async_scoping_repo(nwo)
    return Promise.resolve(nil) unless nwo

    repo_promise = Platform::Loaders::RepositoryByNwo.load(nwo).then do |repo|
      next unless repo
      repo.async_readable_by?(dashboard.user).then do |readable|
        repo if readable
      end
    end
    repo_promise.then do |repo|
      repo || raise(Platform::Errors::NotFound, "Could not resolve to a Repository with the name '#{nwo}'.")
    end
  end

  def fetch_repo_nwo(shortcut_hash)
    return unless repo_hash = shortcut_hash[:scoping_repository]

    "#{repo_hash[:owner]}/#{repo_hash[:name]}"
  end

  # Internal: Build up a list of errors for the given shortcut inputs.
  #
  # These validations are redundant with the existing validations in the
  # SearchShortcut model, this mutation saves shortcuts in bulk without validation.
  # This method ensure validation is consistent with the model.
  #
  # Returns an Array of Hashes with a path and message for each error.
  def validate_shortcuts(shortcuts)
    errors = []

    if shortcuts.size > ::SearchShortcut::MAX_PER_DASHBOARD
      return errors << {
        path: %w[input shortcuts],
        message: "Cannot have more than #{::SearchShortcut::MAX_PER_DASHBOARD} shortcuts"
      }
    end

    shortcuts.each_with_index do |shortcut, index|
      if shortcut[:name].blank?
        errors << {
          path: ["input", "shortcuts", index.to_s, "name"],
          message: "Name can't be blank"
        }
      elsif shortcut[:name].to_s.bytesize > ::SearchDisplayable::NAME_BYTESIZE_LIMIT
        max_chars = ::SearchDisplayable::NAME_BYTESIZE_LIMIT / 4
        errors << {
          path: ["input", "shortcuts", index.to_s, "name"],
          message: "Name is too long (maximum is #{max_chars} characters)"
        }
      end

      if shortcut[:query].to_s.bytesize > MYSQL_UNICODE_BLOB_LIMIT
        max_chars = MYSQL_UNICODE_BLOB_LIMIT / 4
        errors << {
          path: ["input", "shortcuts", index.to_s, "query"],
          message: "Query is too long (maximum is #{max_chars} characters)"
        }
      end
    end

    errors
  end

  class Result
    attr_reader :success, :errors
    alias_method :success?, :success

    def initialize(success:, errors:)
      @success = success
      @errors = errors
    end

    def self.success
      new(
        success: true,
        errors: [],
      )
    end

    def self.failure(errors:)
      new(
        success: false,
        errors: errors,
      )
    end
  end
end
