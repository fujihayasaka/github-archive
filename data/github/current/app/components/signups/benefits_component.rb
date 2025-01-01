# typed: strict
# frozen_string_literal: true

module Signups
  class BenefitsComponent < ApplicationComponent
    BENEFITS = T.let([
      {
        title: "Access to GitHub Copilot",
        description: "Increase your productivity and accelerate software development."
      },
      {
        title: "Unlimited repositories",
        description: "Collaborate securely on public and private projects."
      },
      {
        title: "Integrated code reviews",
        description: "Boost code quality with built-in review tools."
      },
      {
        title: "Automated workflows",
        description: "Save time with CI/CD integrations and GitHub Actions."
      },
      {
        title: "Community support",
        description: "Connect with developers worldwide for instant feedback and insights."
      },
    ].freeze, T::Array[T::Hash[Symbol, String]])
  end
end
