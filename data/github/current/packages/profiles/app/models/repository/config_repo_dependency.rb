# typed: false
# frozen_string_literal: true

module Repository::ConfigRepoDependency
  delegate :preferred_readme, to: :default_directory, allow_nil: true

  def user_configuration_repository?
    async_user_configuration_repository?.sync
  end

  def async_user_configuration_repository?
    async_owner.then do |owner|
      owner&.user? && name.casecmp?(owner.config_repo_name)
    end
  end

  def is_org_profile_repository?
    owner.organization? && owner.configuration_repository&.id == id
  end

  # The org profile readme is located at `/profile/README.md`
  def org_profile_readme
    @org_profile_readme ||= if is_org_profile_repository?
      PreferredFile.find(
        directory: default_directory,
        type: :readme,
        subdirectories: ["profile"]
      )
    else
      nil
    end
  end

  # return true if the org_profile_readme is present
  def has_org_profile_readme?
    org_profile_readme.present?
  end

  def is_org_member_profile_repository?
    owner.organization? && owner.private_configuration_repository&.id == id
  end

  # The org profile readme is located at `/profile/README.md`
  def org_member_profile_readme
    @org_member_profile_readme ||= if is_org_member_profile_repository?
      PreferredFile.find(
        directory: default_directory,
        type: :readme,
        subdirectories: ["profile"]
      )
    else
      nil
    end
  end

  # return true if the org_profile_readme is present
  def has_org_member_profile_readme?
    org_member_profile_readme.present?
  end

  def has_readme?
    return false unless default_directory
    default_directory.has_readme?
  end

  def default_directory
    return @default_directory if defined?(@default_directory)
    @default_directory = directory(default_branch)
  end

  # Generates the initial contents of the profile/README.md file
  def generate_org_profile_readme
    if is_org_profile_repository?
      # This content lives in Repository::ConfigRepoDependency
      org_profile_readme_template
    else
      ""
    end
  end

  # Generates the initial contents of the private profile/README.md file
  def generate_org_member_profile_readme
    if is_org_member_profile_repository?
      # This content lives in Repository::ConfigRepoDependency
      org_member_profile_readme_template
    else
      ""
    end
  end

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

  def configuration_repository_readme_template
    <<~MARKDOWN
      ## Hi there 👋

      <!--
      **#{escape_generated_readme_html(nwo)}** is a ✨ _special_ ✨ repository because its `README.md` (this file) appears on your GitHub profile.

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
