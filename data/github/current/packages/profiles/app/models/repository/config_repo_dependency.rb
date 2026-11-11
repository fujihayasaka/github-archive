# typed: strict
# frozen_string_literal: true

module Repository::ConfigRepoDependency
  extend T::Helpers
  include GitHub::Memoizer

  UNIVERSAL_CONFIG_NAME = ".github"
  CONFIG_PRIVATE_REPO_NAME = ".github-private"
  UNIVERSAL_PROFILE_README_DIRECTORY = "profile"
  README_FILENAME = "README.md"

  delegate :preferred_readme, to: :default_directory, allow_nil: true

  requires_ancestor { Repository }

  sig { returns(T::Boolean) }
  def user_configuration_repository?
    async_user_configuration_repository?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_user_configuration_repository?
    async_owner.then do |owner|
      owner&.user? && name.casecmp?(owner.config_repo_name)
    end
  end

  sig { returns(T::Boolean) }
  def is_org_profile_repository?
    owner&.organization? && owner&.configuration_repository&.id == id
  end

  # The org profile readme is located at `/profile/README.md`
  sig { returns(T.nilable(TreeEntry)) }
  memoize def org_profile_readme
    return unless is_org_profile_repository?

    PreferredFile.find(
      directory: default_directory,
      type: :readme,
      subdirectories: [UNIVERSAL_PROFILE_README_DIRECTORY]
    )
  end

  # return true if the org_profile_readme is present
  sig { returns(T::Boolean) }
  def has_org_profile_readme?
    org_profile_readme.present?
  end

  sig { returns(T::Boolean) }
  def is_org_member_profile_repository?
    this_owner = owner
    return false unless this_owner.present?
    return false unless this_owner.organization?

    T.cast(this_owner, Organization).private_configuration_repository&.id == id
  end

  # Public: Is this repository being used as the configuration repository for the owner?
  sig { returns(T::Boolean) }
  def profile_configuration_repository?
    owner&.configuration_repository&.id == id
  end

  sig { returns(Promise[T::Boolean]) }
  def async_profile_configuration_repository?
    async_owner.then do |owner|
      next false unless owner.present?
      owner.async_configuration_repository.then do |config_repo|
        next false unless config_repo.present?
        config_repo.id == id
      end
    end
  end

  # Public: Is this the configuration repository being used for the owner,
  #         and is it the universal `.github` repo?
  sig { returns(T::Boolean) }
  def universal_configuration_repository?
    return false unless profile_configuration_repository?
    name == UNIVERSAL_CONFIG_NAME
  end

  sig { returns(Promise[T::Boolean]) }
  def async_universal_configuration_repository?
    async_profile_configuration_repository?.then do |is_config_repo|
      next false unless is_config_repo
      name == UNIVERSAL_CONFIG_NAME
    end
  end

  # Public: If this is a configuration repository, get the profile README, if it exists.
  sig { returns(T.nilable(TreeEntry)) }
  memoize def profile_readme
    return unless profile_configuration_repository?

    if universal_configuration_repository?
      PreferredFile.find(
        directory: default_directory,
        type: :readme,
        subdirectories: [UNIVERSAL_PROFILE_README_DIRECTORY]
      )
    else
      preferred_readme
    end
  end

  sig { returns(Promise[T.nilable(TreeEntry)]) }
  def async_profile_readme
    async_profile_configuration_repository?.then do |is_config_repo|
      next unless is_config_repo

      async_universal_configuration_repository?.then do |is_universal_repo|
        if is_universal_repo
          PreferredFile.find(
            directory: default_directory,
            type: :readme,
            subdirectories: [UNIVERSAL_PROFILE_README_DIRECTORY]
          )
        else
          async_preferred_readme
        end
      end
    end
  end

  # Public: Does this repository contain the profile README that is being used for the repo owner?
  sig { returns(T::Boolean) }
  def has_profile_readme?
    profile_readme.present?
  end

  # The org profile readme is located at `/profile/README.md`
  sig { returns(T.nilable(TreeEntry)) }
  memoize def org_member_profile_readme
    return unless is_org_member_profile_repository?

    PreferredFile.find(
      directory: default_directory,
      type: :readme,
      subdirectories: [UNIVERSAL_PROFILE_README_DIRECTORY]
    )
  end

  # return true if the org_profile_readme is present
  sig { returns(T::Boolean) }
  def has_org_member_profile_readme?
    org_member_profile_readme.present?
  end

  sig { returns(T::Boolean) }
  def has_readme?
    this_default_directory = default_directory
    return false unless this_default_directory.present?
    this_default_directory.has_readme?
  end

  sig { returns(T.nilable(Directory)) }
  memoize def default_directory
    directory(default_branch)
  end

  # Public: Generates the default text to use for the profile README.
  sig { returns(String) }
  def generate_profile_readme
    return "" unless profile_configuration_repository? || is_org_member_profile_repository?

    if is_org_profile_repository?
      org_profile_readme_template
    elsif is_org_member_profile_repository?
      org_member_profile_readme_template
    else
      configuration_repository_readme_template
    end
  end

  # Generates the initial contents of the profile/README.md file
  sig { returns(String) }
  def generate_org_profile_readme
    if is_org_profile_repository?
      # This content lives in Repository::ConfigRepoDependency
      org_profile_readme_template
    else
      ""
    end
  end

  # Generates the initial contents of the private profile/README.md file
  sig { returns(String) }
  def generate_org_member_profile_readme
    if is_org_member_profile_repository?
      # This content lives in Repository::ConfigRepoDependency
      org_member_profile_readme_template
    else
      ""
    end
  end

  # Public: The expected path to the profile README for this repository.
  sig { returns(String) }
  def expected_profile_readme_path
    if name == UNIVERSAL_CONFIG_NAME || name == CONFIG_PRIVATE_REPO_NAME
      "#{UNIVERSAL_PROFILE_README_DIRECTORY}/#{README_FILENAME}"
    else
      README_FILENAME
    end
  end

  sig { returns(String) }
  def org_profile_readme_template
    <<~MARKDOWN
      ## Hi there 👋

      <!--

      **Here are some ideas to get you started:**

      🙋‍♀️ A short introduction - what is your organization all about?
      🌈 Contribution guidelines - how can the community get involved?
      👩‍💻 Useful resources - where can the community find your docs? Is there anything else the community should know?
      🍿 Fun facts - what does your team eat for breakfast?
      🧙 Remember, you can do mighty things with the power of [Markdown](https://docs.github.com/github/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
      -->
    MARKDOWN
  end

  sig { returns(String) }
  def org_member_profile_readme_template
    <<~MARKDOWN
      ## Welcome to the team 🙌

      <!--

      **Here are some ideas to get you started:**

      🙋‍♀️ A short introduction - what is your organization all about?
      👀 Contribution guidelines - how do team members dive in?
      👩‍💻 Useful resources - where do you keep your docs? Is there anything else the team should know?
      🍪 Fun facts - what is your team's favorite snack?
      🧙 Remember, you can do mighty things with the power of [Markdown](https://docs.github.com/github/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
      -->
    MARKDOWN
  end

  sig { returns(String) }
  def configuration_repository_readme_template
    <<~MARKDOWN
      ## Hi there 👋

      <!--
      **#{escape_generated_readme_html(nwo)}** is a ✨ _special_ ✨ repository because its `#{expected_profile_readme_path}` (this file) appears on your GitHub profile.

      Here are some ideas to get you started:

      - 🔭 I’m currently working on ...
      - 🌱 I’m currently learning ...
      - 👯 I’m looking to collaborate on ...
      - 🤔 I’m looking for help with ...
      - 💬 Ask me about ...
      - 📫 How to reach me: ...
      - 😄 Pronouns: ...
      - ⚡ Fun fact: ...
      -->
    MARKDOWN
  end
end
