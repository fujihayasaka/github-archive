# typed: false
# frozen_string_literal: true

module User::ProfileReadmeDependency
  # Public: Whether or not the user has a profile readme,
  #         regardless of visiblity
  #
  # Returns a boolean
  def has_profile_readme?
    return false unless has_configuration_repository?
    configuration_repository.has_readme?
  end

  # Public: The user's profile readme if one exists,
  #         regardless of visiblity
  #
  # Returns a TreeEntry or nil
  def profile_readme
    configuration_repository&.preferred_readme
  end

  def async_profile_readme
    async_configuration_repository.then do |repo|
      repo&.async_preferred_readme
    end
  end

  # Public: Whether or not the user is in the correct state
  #         to display a profile readme
  #
  # Returns a boolean
  def eligible_to_display_profile_readme?
    async_eligible_to_display_profile_readme?.sync
  end

  def async_eligible_to_display_profile_readme?
    return Promise.resolve(false) if spammy?

    async_profile.then do |profile|
      next false unless profile
      profile.readme_opt_in?
    end
  end

  # Public: Whether or not the the users's profile readme
  #         is currently visible on their profile
  #
  # Returns a boolean
  def profile_readme_visible?
    timer = Timer.start
    result = async_profile_readme_visible?.sync
    timer.stop
    GitHub.dogstats.distribution("profile_readme_check", timer.elapsed_ms, tags: ["readme_found:#{result}", "type:user"])
    result
  end

  def async_profile_readme_visible?
    async_eligible_to_display_profile_readme?.then do |is_eligible|
      next false unless is_eligible

      async_configuration_repository.then do |repo|
        next false unless repo&.public?

        # As of now, it's necessary to check both disabled? methods.
        # See https://github.com/github/github/pull/148922/files#r452507975
        # for details
        next false if repo.disabled?
        next false if repo.access.disabled?

        async_profile_readme.then do |readme|
          next false unless readme
          !readme.data.blank?
        end
      end
    end
  end

  # Public: The quick start template for a profile readme. This is used for the
  #         ProfileReadmeZeroBannerComponent displayed on the dashboard.
  #
  # include_comment - A Boolean indicating if a comment explaining profile readmes
  #                   should be appended to the template.
  #
  # Returns a String.
  def profile_readme_quick_start_template(include_comment: true)
    template = <<~MARKDOWN
      - 👋 Hi, I’m @#{login}
      - 👀 I’m interested in ...
      - 🌱 I’m currently learning ...
      - 💞️ I’m looking to collaborate on ...
      - 📫 How to reach me ...
      - 😄 Pronouns: ...
      - ⚡ Fun fact: ...

    MARKDOWN

    if include_comment
      template = template + <<~MARKDOWN
      <!---
      #{login}/#{config_repo_name} is a ✨ special ✨ repository because its `README.md` (this file) appears on your GitHub profile.
      You can click the Preview link to take a look at your changes.
      --->
      MARKDOWN
    end

    template
  end

  def profile_readme_path
    profile_readme.path.force_encoding("UTF-8")
  end

  def profile_readme_filename
    profile_readme_path.split(".").first
  end

  def profile_readme_file_extension
    profile_readme_path.split(".").last
  end
end
