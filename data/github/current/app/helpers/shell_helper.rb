# typed: true
# frozen_string_literal: true

module ShellHelper
  include Kernel
  # This is a very conservative definition of "safe" shell characters,
  # consisting only of ASCII letters, digits, forward slashes, underscores,
  # periods, and hyphens.
  SHELL_SAFE_REGEX = %r{\A[a-z0-9/_.-]+\z}i

  # Anything that doesn't contain single quotes or backslashes can be made
  # safe in Bash, Zsh, Fish, PowerShell by single-quoting.
  SHELL_SAFE_IF_QUOTED_REGEX = /\A[^\\']+\z/i

  # Public: Returns a sanitized version of name suitable for passing as an
  # argument to a shell command. The name is derived from `template`,
  # substituting any placeholders of the form ":word" with the next value from
  # `substitutions`.
  #
  # Example templates that we're currently using in our views include:
  #
  # - :branch
  # - :user-:branch
  # - origin/:branch
  #
  # If the name contains only shell-safe characters it will be returned in
  # literal form (eg. "origin/main"). If it contains characters that are safe if
  # quoted, it will return a quoted form (eg. "'origin/two words'"). Otherwise,
  # it will include a visible placeholder in the text (eg. "<BRANCH>" or
  # "origin/<BRANCH>" or similar).
  def shell_safe_name(template, *substitutions)
    requires_quoting = T.let(false, T::Boolean)

    # Break the template into tokens (eg. ":user-:branch" tokenizes as "",
    # ":user", "-", ":branch"), and build up the output token-by-token.
    output = ""
    template.split(/(:[a-z]+)/i).map do |placeholder_or_text|
      if placeholder_or_text.start_with?(":")
        placeholder = placeholder_or_text.delete_prefix(":")
        raise ArgumentError, "Too many placeholders" if substitutions.count.zero?
        text = substitutions.shift.to_s
      else
        placeholder = nil
        text = placeholder_or_text
      end

      unless text.length.zero?
        hyphen_at_start = output.length.zero? && text.start_with?("-")
        potentially_safe = !hyphen_at_start && text.valid_encoding?
        if potentially_safe && text.match(SHELL_SAFE_REGEX)
          output += text
        elsif potentially_safe && text.match(SHELL_SAFE_IF_QUOTED_REGEX)
          output += text
          requires_quoting = true
        elsif placeholder.present?
          output += "<#{placeholder.upcase}>"
        elsif hyphen_at_start
          raise ArgumentError, "Text must not start with a hyphen"
        else
          raise ArgumentError, "Template text contains unsafe characters"
        end
      end
    end
    raise ArgumentError, "Too many substitutions" unless substitutions.count.zero?

    requires_quoting ? "'#{output}'" : output
  end

  SHELL_ESCAPING_DOCS_URL = "https://docs.github.com/get-started/using-git/dealing-with-special-characters-in-branch-and-tag-names"

  # Public: Given a series of untrusted, user-supplied inputs, checks to see
  # whether _any_ of them cannot be safely quoted or escaped in a way that works
  # in _all_ commonly used shells (eg. Bash/Zsh-alikes, Fish, PowerShell).
  #
  # Specifically, this method pipes the inputs through `shell_safe_name()`, and
  # returns `true` if _any_ of the resulting values includes a "<BRANCH>" (or
  # similar) placeholder. A return value of `true` is an indication that we
  # should link to the docs on how to do shell-escaping.
  def shell_safe_names_include_placeholders?(templates_and_substitutions)
    templates_and_substitutions.any? do |template_and_substitutions|
      name = shell_safe_name *template_and_substitutions

      # Bail as soon as we see a name that looks sketchy.
      !name.valid_encoding? || name.include?("<")
    end
  end
end
