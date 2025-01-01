# typed: false
# frozen_string_literal: true

module EditorConfigHelper
  DEFAULT_TAB_SIZE = 8
  DEFAULT_SOFT_TAB_SIZE = 2
  MIN_TAB_SIZE = 1
  MAX_TAB_SIZE = 12

  def load_blob_editor_configs!(commit, blob, timeout = 0.3)
    return unless commit
    # TODO: GIST!!!
    return unless current_repository.respond_to?(:load_editor_config)
    @editor_configs = current_repository.load_editor_config(commit, [blob.path], timeout)
  end

  def load_diff_editor_configs!(diff)
    return unless diff.available?
    # TODO: GIST!!!
    return unless diff.repo.respond_to?(:load_editor_config)
    commit = diff.repo.commits.find(diff.sha2)
    @editor_configs = diff.repo.load_editor_config(commit, diff.to_a.map(&:path))
  end

  def cast_tab_width(n)
    n = n.to_i
    (n >= MIN_TAB_SIZE && n <= MAX_TAB_SIZE) ? n : nil
  end

  def editor_config_indent_style(path)
    @editor_configs ||= {}
    if config = @editor_configs[path]
      config["indent_style"]
    end
  end

  def editor_config_indent_size(path)
    @editor_configs ||= {}
    if config = @editor_configs[path]
      cast_tab_width config["indent_size"]
    end
  end

  def editor_config_tab_width(path)
    @editor_configs ||= {}
    if config = @editor_configs[path]
      cast_tab_width config["tab_width"]
    end
  end

  def param_tab_size
    cast_tab_width params[:ts]
  end

  # If a user has the default tab size set we want to effectively ignore it
  # and defer to the editor config setting
  def user_tab_size
    return unless logged_in?
    setting_value = current_user.settings.get(:tab_size)
    UserSettings.is_default_value?(:tab_size, setting_value) ? nil : setting_value
  end

  def tab_size(path)
    if param_tab_size
      param_tab_size
    elsif user_tab_size
      user_tab_size
    elsif config_tab_width = editor_config_tab_width(path)
      GitHub.dogstats.increment("editorconfig.tab_size_override") if config_tab_width != DEFAULT_TAB_SIZE
      config_tab_width
    else
      DEFAULT_TAB_SIZE
    end
  end

  # Does the given chunk of code use soft tabs (spaces) for indentation or hard
  # tabs (\t)? This method tries to figure it out/
  #
  # blob - Blob object
  #
  # Returns "tab" or "space".
  def guess_indent_style(blob)
    blob.data =~ /^\t/m ? "tab" : "space"
  end

  # Tries to figure out the tab size, ie number of spaces per indent or "tab",
  # in a chunk of code.
  #
  # blob - Blob object
  #
  # Returns a Integer.
  def guess_indent_size(blob)
    if guess_indent_style(blob) == "space"
      match = blob.data.match(/^( +)[^*]/im)
      cast_tab_width match ? match[1].length : DEFAULT_SOFT_TAB_SIZE
    else
      DEFAULT_TAB_SIZE
    end
  end

  def blob_editor_wrap_mode(blob)
    blob.language.try(:wrap) ? "on" : "off"
  end

  def blob_editor_indent_style(blob)
    indent_style_config = editor_config_indent_style(blob.path)
    if indent_style_config.present? && indent_style_config != guess_indent_style(blob)
      GitHub.dogstats.increment("editorconfig.indent_style_override")
      return indent_style_config
    end
    guess_indent_style(blob)
  end

  def blob_editor_indent_size(blob)
    indent_size_config = editor_config_indent_size(blob.path)
    if indent_size_config.present? && indent_size_config != guess_indent_size(blob)
      GitHub.dogstats.increment("editorconfig.indent_size_override")
      return indent_size_config
    end
    guess_indent_size(blob)
  end
end
