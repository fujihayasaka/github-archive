# typed: strict
# frozen_string_literal: true

module User::ProfileReadmeDependency
  extend T::Helpers

  requires_ancestor { User }

  ALTERNATE_REPO_README_DIRECTORY = "profile"

  # Public: Whether or not the user has a profile readme,
  #         regardless of visiblity
  sig { returns(T::Boolean) }
  def has_profile_readme?
    return false unless has_configuration_repository?
    config_repo = T.must_because(configuration_repository) { "required by `has_configuration_repository?`" }

    if using_alternate_configuration_repository?
      profile_readme.present?
    else
      config_repo.has_readme?
    end
  end

  # Public: The user's profile readme if one exists,
  #         regardless of visiblity
  sig { returns(T.nilable(TreeEntry)) }
  def profile_readme
    if using_alternate_configuration_repository?
      config_repo = T.must_because(configuration_repository) { "required by `using_alternate_configuration_repository?`" }

      PreferredFile.find(
        directory: config_repo.directory(config_repo.default_branch),
        type: :readme,
        subdirectories: [ALTERNATE_REPO_README_DIRECTORY]
      )
    else
      configuration_repository&.preferred_readme
    end
  end

  sig { returns(Promise[T.nilable(TreeEntry)]) }
  def async_profile_readme
    async_configuration_repository.then do |repo|
      return Promise.resolve(T.let(nil, T.nilable(TreeEntry))) unless repo.present?

      async_using_alternate_configuration_repository?.then do |is_using_alt_repo|
        if is_using_alt_repo
          repo.async_default_branch.then do |default_branch|
            PreferredFile.find(
              directory: repo.directory(default_branch),
              type: :readme,
              subdirectories: [ALTERNATE_REPO_README_DIRECTORY]
            )
          end
        else
          repo.async_preferred_readme
        end
      end
    end
  end

  # Public: Whether or not the user is in the correct state
  #         to display a profile readme
  sig { returns(T::Boolean) }
  def eligible_to_display_profile_readme?
    async_eligible_to_display_profile_readme?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_eligible_to_display_profile_readme?
    return Promise.resolve(T.let(false, T::Boolean)) if spammy?

    async_profile.then do |profile|
      next false unless profile
      profile.readme_opt_in?
    end
  end

  # Public: Whether or not the the users's profile readme
  #         is currently visible on their profile
  sig { returns(T::Boolean) }
  def profile_readme_visible?
    timer = Timer.start
    result = async_profile_readme_visible?.sync
    timer.stop
    GitHub.dogstats.distribution("profile_readme_check", timer.elapsed_ms, tags: ["readme_found:#{result}", "type:user"])
    result
  end

  sig { returns(Promise[T::Boolean]) }
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
  sig { params(include_comment: T::Boolean).returns(String) }
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

  sig { returns(T.nilable(String)) }
  def profile_readme_path
    profile_readme&.path.force_encoding("UTF-8")
  end

  sig { returns(T.nilable(String)) }
  def profile_readme_filename
    profile_readme_path&.split(".")&.first
  end

  sig { returns(T.nilable(String)) }
  def profile_readme_file_extension
    profile_readme_path&.split(".")&.last
  end
end
