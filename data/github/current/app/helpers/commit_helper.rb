# typed: false
# frozen_string_literal: true

module CommitHelper
  MAX_DISPLAYED_COMMIT_AVATARS = 3

  # Link to a commit page using commit's short message as the link text. This
  # handles linkifying when other <a> tags exist in the processed commit message
  # string.
  #
  # commit - A Commit object.
  # url - The URL to link to, defaults to the commit's path.
  # commit_message - Specific commit message string.
  # options - A Hash of options to pass to link_to.
  #          :use_default_font_color - Boolean to use the default font color.
  #          :include_title - Boolean to include the commit message as the link title attribute.
  #
  # Returns the HTML markup as a String.
  def commit_short_message_link(commit, url = commit_path(commit), commit_message = nil, options = {})
    message = commit_message ? commit_message : commit.short_message_html
    message = commit_message_markdown(message)

    default_options = {
      use_default_font_color: false,
      include_title: true
    }

    opts = default_options.merge(options)

    attrs = {
      "data-pjax" => true,
    }

    attrs[:title] = commit.message_text.tooltip if opts[:include_title]

    unless commit_message.present? || opts[:use_default_font_color]
      attrs[:class] = "Link--secondary"
    end

    if opts[:use_default_font_color]
      attrs[:class] = "color-fg-default"
    end

    link_markup_to message, url, attrs
  end

  # Returns the hotkey for navigating to the parent commit
  #
  # parent_number - an Integer
  #
  # Returns "p", "o", or nil (if the parent_number is 2 or greater)
  def parent_hotkey(parent_number)
    case parent_number
    when 0 then "p"
    when 1 then "o"
    else nil
    end
  end

  # Link to the user page for either the author or committer on a commit. If no
  # user exists for the email, just write the actor's name.
  #
  # commit  - A Commit object.
  # type    - Either :author or :committer.
  # options - Anything that can be passed in link_to options. The :truncate
  #           option is used a lot.
  #
  # Returns HTML content wrapped in an <a> or <span> depending on whether a user
  # exists for the author.
  def link_to_commit_actor(commit, type, options = {})

    unless type == :author || type == :committer
      raise ArgumentError, "type must be :author or :committer"
    end

    if user = commit.send(type)
      options[:rel] = find_rel_type(user)
      profile_link user, options
    else
      name  = try_guess_and_transcode commit.__send__("#{type}_name").to_s

      if name.blank?
        content_tag :span, "Unknown",
          :class => ["tooltipped", options[:class]].compact.join(" "),
          "aria-label" => "Oops! This commit is missing author information."
      elsif options[:truncate] && name.size > 15
        content_tag :span, truncate(name, length: 15),
          :class => ["tooltipped", options[:class]].compact.join(" "),
          "aria-label" => h(name)
      else
        content_tag :span, name, options
      end
    end
  end

  # Is the commit author the same as the commit committer? This special cases
  # the "GitHub" committer, which we usually want to ignore in the UI.
  #
  # commit - A Commit instance.
  #
  # Returns boolean.
  def committer_is_author?(commit)
    return true if committed_via_github?(commit)

    if commit.author.nil? || commit.committer.nil?
      commit.committer_email.downcase == commit.author_email.downcase
    else
      commit.author == commit.committer
    end
  end

  # Was this commit made using the GitHub web UI? We determine this by checking
  # the committer name and email.
  #
  # commit - A Commit instance.
  #
  # Returns boolean.
  def committed_via_github?(commit)
    CommitHelper.via_github?(
      committer_name: commit.committer_name,
      committer_email: commit.committer_email,
    )
  end

  def self.via_github?(committer_name:, committer_email:)
    committer_name == GitHub.web_committer_name &&
    committer_email == GitHub.web_committer_email
  end

  def spoofed_commit_check_cache_key(commit)
    parts = [
      "v1",
      "spoofed_commit_check",
      commit&.repository&.name_with_owner,
      commit&.oid,
      commit&.repository&.pushed_at,
    ].compact

    "spoofed_commit_check:#{Digest::SHA256.hexdigest(parts.join(":"))}"
  end

  def commit_branches_cache_key(commit)
    parts = [
      "v4",
      "commit-branches",
      commit.repository.name_with_owner,
      commit.oid,
      commit.repository.pushed_at,
      "with-merged-pr",  # remove this the next time this key is changed
    ].compact

    "commit_branches:#{Digest::SHA256.hexdigest(parts.join(":"))}"
  end

  def prefill_for_condensed_commit_view(commits, viewer)
    commits.group_by(&:repository).each do |repository, commits|
      Commit.prefill_comment_counts(commits, repository)
    end

    Promise.all(commits.flat_map do |commit|
      [
        commit.author_actors.map { |git_actor| git_actor.async_visible_actor(viewer) },
        commit.committer_actor.async_visible_actor(viewer),
        commit.async_authored_by_committer?,
        commit.async_has_status_check_rollup?,
        commit.async_short_message_html,
        commit.async_message_body_html,
      ].flatten
    end).sync
  end
end
