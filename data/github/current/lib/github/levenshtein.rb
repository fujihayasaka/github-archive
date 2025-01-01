# typed: true
# frozen_string_literal: true

module GitHub
  class Levenshtein
    # Compare the similarity between two strings.
    #
    # Examples
    #
    #   GitHub::Levenshtein.similarity("dog", "dog")
    #   # => 1.0
    #
    #   GitHub::Levenshtein.similarity("dog", "dog!")
    #   # => 0.75
    #
    #   GitHub::Levenshtein.similarity("dog", "cat")
    #   # => 0.0
    #
    # Returns a percentage between 0.0 and 1.0.
    def self.similarity(a, b)
      return 0 if a.nil? || b.nil?
      return 0 if a.empty? || b.empty?
      dist = ::Levenshtein.distance(a, b)
      max = [a.size, b.size].max
      1 - dist.to_f / max
    end
  end
end
