# typed: true
# frozen_string_literal: true

module CodeScanning::DefaultSetupHelper
  extend T::Helpers

  include LanguageHelper

  def auto_codeql_language_name(language)
    case language
    when "actions"
      "GitHub Actions"
    when "c-cpp"
      "C / C++"
    when "csharp"
      "C#"
    when "java-kotlin"
      "Java / Kotlin"
    when "javascript-typescript"
      "JavaScript / TypeScript"
    else
      language.capitalize
    end
  end

  def auto_codeql_language_color(language)
    linguist_name = case language
    when "c-cpp"
      "C"
    when "csharp"
      "C#"
    when "java-kotlin"
      "Java"
    when "javascript-typescript"
      "JavaScript"
    else
      language.capitalize
    end
    language_color(Linguist::Language[linguist_name])
  end
end
